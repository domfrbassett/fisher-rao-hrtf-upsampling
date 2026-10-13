function summary = run_streaming_evaluation(seedDataset, upsamplers, sampling, cfg)
% Evaluate one subject/method/condition row at a time and checkpoint output.

    ensure_results_folder(cfg.resultsRoot);
    ensure_results_folder(cfg.execution.tensorRoot);
    evaluationSubjectIds = table(cfg.validationIds(:), ...
        'VariableNames', {'subjectId'});
    writetable(evaluationSubjectIds, cfg.execution.subjectSelectionCsv);
    summary = table();

    if cfg.execution.resume && isfile(cfg.execution.checkpointMat)
        checkpoint = load(cfg.execution.checkpointMat, "checkpointSummary");
        if isfield(checkpoint, "checkpointSummary")
            summary = checkpoint.checkpointSummary;
        end
    end
    rowsBeforePruning = height(summary);
    summary = prune_summary_to_current_configuration( ...
        summary, upsamplers, sampling, cfg);
    rowsAfterPruning = height(summary);

    if cfg.execution.perceptualOnly
        assert(~isempty(summary), ...
            ["Perceptual-only execution requires the completed full " ...
             "evaluation checkpoint in cfg.resultsRoot."]);
        selectedPerceptualRows = ...
            ismember(summary.method, cfg.perceptual.methods) & ...
            ismember(summary.retainedDirections, ...
                cfg.perceptual.retentionConditions);
        perceptualComplete = ~selectedPerceptualRows | ...
            (summary.perceptualStatus == "completed" & ...
            summary.perceptualTrials == cfg.perceptual.numExperiments);
        if cfg.perceptual.reportRelativeToSelf
            perceptualComplete = ~selectedPerceptualRows | ...
                (perceptualComplete & summary.selfPerceptualTrials == ...
                    cfg.perceptual.numExperiments);
        end
        perceptualComplete = perceptualComplete | ...
            summary.perceptualStatus == "not_applicable";
        completedKeys = completed_summary_keys(summary(perceptualComplete, :));
    else
        completedKeys = completed_summary_keys(summary);
    end
    nRows = numel(cfg.validationIds) * numel(sampling) * numel(upsamplers);
    completedRows = numel(completedKeys);
    append_progress_log(cfg, sprintf( ...
        "Starting/resuming evaluation with %d of %d rows complete.", ...
        completedRows, nRows));
    if rowsBeforePruning ~= rowsAfterPruning
        append_progress_log(cfg, sprintf( ...
            "Pruned %d checkpoint rows outside the current subject/method/retention configuration.", ...
            rowsBeforePruning - rowsAfterPruning));
    end
    append_progress_log(cfg, sprintf( ...
        "Evaluation cohort: %d declared SONICOM subjects, IDs %d to %d.", ...
        numel(cfg.validationIds), min(cfg.validationIds), ...
        max(cfg.validationIds)));

    % Required for Fisher cue extraction as well as observer simulation.
    barumerliCompatibilityCleanup = activate_barumerli_compatibility(cfg); %#ok<NASGU>

    seedTarget = seedDataset(1);
    for iSubject = 1:numel(cfg.validationIds)
        target = load_streaming_subject(seedTarget, cfg.validationIds(iSubject), cfg);
        referenceTemplate = struct();
        hasReferenceTemplate = false;
        targetCueCache = struct();
        selfReference = not_run_perceptual_result("not_run", ...
            "Self-reference reporting disabled in configuration.");
        if cfg.runPerceptualModel && cfg.perceptual.reportRelativeToSelf
            [selfReference, hasSelfReference] = ...
                saved_self_reference_result(summary, target.subjectId, cfg);
            if ~hasSelfReference
                referenceTemplate = create_barumerli_template(target, cfg);
                hasReferenceTemplate = true;
                referenceProgress = sprintf( ...
                    "Processing dense self-reference: subject %d.", ...
                    target.subjectId);
                fprintf("%s\n", referenceProgress);
                append_progress_log(cfg, referenceProgress);
                selfReference = evaluate_barumerli_model( ...
                    referenceTemplate, target, target, cfg, struct());
            end
            summary = apply_self_reference_to_existing_rows( ...
                summary, target.subjectId, selfReference, cfg);
            if ~isempty(summary)
                write_streaming_checkpoint(summary, cfg);
            end
        end

        for iCondition = 1:numel(sampling)
            sparseField = subset_spatial_field(target, ...
                sampling(iCondition).retainedIndices);

            for iMethod = 1:numel(upsamplers)
                method = upsamplers(iMethod);
                rowKey = evaluation_row_key(target.subjectId, ...
                    sampling(iCondition).retentionCount, method.name);
                if ismember(rowKey, completedKeys)
                    continue;
                end

                progress = sprintf( ...
                    "Processing row %d/%d: subject %d, %s, N=%d.", ...
                    completedRows + 1, nRows, target.subjectId, method.name, ...
                    sampling(iCondition).retentionCount);
                fprintf("%s\n", progress);
                append_progress_log(cfg, progress);

                recon = reconstruct_hrtf_field(sparseField, target.r, method, cfg);
                if cfg.execution.perceptualOnly
                    rowIndex = find(summary.subjectId == target.subjectId & ...
                        summary.retainedDirections == ...
                            sampling(iCondition).retentionCount & ...
                        summary.method == method.name);
                    assert(isscalar(rowIndex), ...
                        "Expected exactly one existing summary row for %s.", ...
                        rowKey);

                    if ~recon.isAvailable
                        perceptual = not_run_perceptual_result( ...
                            "not_applicable", recon.message);
                    else
                        if ~hasReferenceTemplate
                            referenceTemplate = create_barumerli_template( ...
                                target, cfg);
                            hasReferenceTemplate = true;
                        end
                        perceptual = evaluate_barumerli_model( ...
                            referenceTemplate, target, recon, cfg, struct());
                    end
                    perceptual = attach_self_reference_metrics( ...
                        perceptual, selfReference, cfg);
                    summary = replace_perceptual_summary_row( ...
                        summary, rowIndex, perceptual);

                    completedRows = completedRows + 1;
                    completedKeys(end + 1, 1) = rowKey; %#ok<AGROW>
                    if mod(completedRows, ...
                            cfg.execution.writeCheckpointEveryRows) == 0
                        write_streaming_checkpoint(summary, cfg);
                    end
                    continue;
                end

                signal = evaluate_signal_metrics(target, recon, cfg);
                if recon.isAvailable
                    try
                        [fisher, ~, targetCueCache] = ...
                            evaluate_fisher_tensor_airm( ...
                                target, recon, cfg, targetCueCache);
                    catch fisherError
                        % Record the failure on this row rather than
                        % aborting a multi-day run or emitting a value.
                        failure = "Not applicable: Fisher evaluation failed: " + ...
                            string(fisherError.message);
                        append_progress_log(cfg, failure);
                        fisher = unavailable_fisher_result( ...
                            size(target.r, 1), failure, cfg);
                        recon.isAvailable = false;
                        recon.message = failure;
                    end
                else
                    fisher = unavailable_fisher_result(size(target.r, 1), ...
                        recon.message, cfg);
                end
                write_metric_tensor_files(target, method, sampling(iCondition), ...
                    fisher, cfg);

                if ~cfg.runPerceptualModel
                    perceptual = not_run_perceptual_result("not_run", ...
                        "Perceptual model disabled in configuration.");
                elseif ~is_selected_perceptual_condition(method, ...
                        sampling(iCondition).retentionCount, cfg)
                    perceptual = not_run_perceptual_result("not_selected", ...
                        "Not included in declared Barumerli comparison.");
                elseif ~recon.isAvailable
                    perceptual = not_run_perceptual_result("not_applicable", ...
                        recon.message);
                else
                    if ~hasReferenceTemplate
                        referenceTemplate = create_barumerli_template(target, cfg);
                        hasReferenceTemplate = true;
                    end
                    % Fisher uses PGE features; the LAP-style observer uses
                    % independently extracted DTF target features.
                    perceptual = evaluate_barumerli_model( ...
                        referenceTemplate, target, recon, cfg, struct());
                end
                perceptual = attach_self_reference_metrics( ...
                    perceptual, selfReference, cfg);

                rowSummary = build_airm_summary_table(target, 1, method, ...
                    sampling(iCondition), {recon}, signal, fisher, perceptual);
                if isempty(summary)
                    summary = rowSummary;
                else
                    summary = [summary; rowSummary]; %#ok<AGROW>
                end

                completedRows = completedRows + 1;
                completedKeys(end + 1, 1) = rowKey; %#ok<AGROW>
                if mod(completedRows, ...
                        cfg.execution.writeCheckpointEveryRows) == 0
                    write_streaming_checkpoint(summary, cfg);
                end
            end
        end
    end

    write_streaming_checkpoint(summary, cfg);
    append_progress_log(cfg, sprintf("Completed all %d rows.", nRows));

end

function target = load_streaming_subject(seedTarget, subjectId, cfg)
% Keep only one complete acoustic field in memory during the full study.

    if seedTarget.subjectId == subjectId
        target = seedTarget;
        return;
    end

    subjectCfg = cfg;
    subjectCfg.subjectIds = subjectId;
    loaded = preprocess_hrtf_dataset(load_dense_hrtf_dataset(subjectCfg), cfg);
    assert(isscalar(loaded), ...
        "Expected exactly one SOFA field for subject %d.", subjectId);
    target = loaded(1);
    assert(isequal(size(target.r), size(seedTarget.r)) && ...
        max(abs(target.r - seedTarget.r), [], "all") < ...
        cfg.uniqueDirectionTolerance, ...
        "Subject %d does not share the common direction grid.", subjectId);

end

function keys = completed_summary_keys(summary)

    keys = strings(0, 1);
    if isempty(summary)
        return;
    end

    keys = strings(height(summary), 1);
    for iRow = 1:height(summary)
        keys(iRow) = evaluation_row_key(summary.subjectId(iRow), ...
            summary.retainedDirections(iRow), summary.method(iRow));
    end

end

function summary = prune_summary_to_current_configuration( ...
        summary, upsamplers, sampling, cfg)
% Keep only rows compatible with the currently declared deterministic study.

    if isempty(summary)
        return;
    end

    validMethods = strings(1, numel(upsamplers));
    for iMethod = 1:numel(upsamplers)
        validMethods(iMethod) = upsamplers(iMethod).name;
    end
    validRetentions = [sampling.retentionCount];
    keep = ismember(summary.subjectId, cfg.validationIds) & ...
        ismember(summary.retainedDirections, validRetentions) & ...
        ismember(string(summary.method), validMethods);
    summary = summary(keep, :);

end

function key = evaluation_row_key(subjectId, retentionCount, methodName)

    key = string(sprintf("%d|%d|%s", subjectId, retentionCount, methodName));

end

function write_streaming_checkpoint(summary, cfg)

    checkpointSummary = summary;
    save(cfg.execution.checkpointMat, "checkpointSummary", "-v7.3");
    writetable(summary, cfg.execution.summaryCsv);

end

function append_progress_log(cfg, message)

    fileId = fopen(cfg.execution.progressLog, "a");
    assert(fileId ~= -1, "Unable to open progress log: %s", ...
        cfg.execution.progressLog);
    fileCleanup = onCleanup(@() fclose(fileId));
    fprintf(fileId, "[%s] %s\n", char(datetime("now")), message);

end

function selected = is_selected_perceptual_condition(method, retentionCount, cfg)

    selected = ismember(method.name, cfg.perceptual.methods) && ...
        ismember(retentionCount, cfg.perceptual.retentionConditions);

end
