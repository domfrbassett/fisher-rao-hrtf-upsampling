function results = analyse_2ifc_responses(responseCsv, resultsRoot, cfg)
%ANALYSE_2IFC_RESPONSES Summarise behavioural responses and fit predictors.
%
% responseCsv is downloaded from the study application's /api/export.csv
% endpoint after data collection. Formal trials only are included in the
% primary summary and optional mixed-effects model.

    arguments
        responseCsv (1, 1) string
        resultsRoot (1, 1) string
        cfg.manifestVersion (1, 1) string = "adaptive-v4-grid-native-balanced-subjects"
    end

    if ~isfolder(resultsRoot)
        mkdir(resultsRoot);
    end

    responses = readtable(responseCsv, "TextType", "string");
    assert(ismember("correct", string(responses.Properties.VariableNames)), ...
        "Response export does not include the correct response indicator.");
    formal = responses(responses.blockType == "formal" & ...
        responses.manifestVersion == cfg.manifestVersion, :);
    assert(~isempty(formal), ...
        "No formal behavioural trials were found for manifest %s.", ...
        cfg.manifestVersion);
    if ~ismember("difficultySection", string(formal.Properties.VariableNames))
        formal.difficultySection = repmat("unspecified", height(formal), 1);
    end
    if islogical(formal.correct)
        % Already correctly typed by readtable.
    elseif isnumeric(formal.correct)
        formal.correct = formal.correct ~= 0;
    else
        correctText = lower(strtrim(string(formal.correct)));
        formal.correct = correctText == "true" | correctText == "1";
    end
    formal.predictedDeltaDPrime = formal.predictedDPrimeField - ...
        formal.predictedDPrimeReference;
    isAdaptive = ismember("adaptive", string(formal.Properties.VariableNames)) && ...
        any(parse_logical(formal.adaptive));

    summary = groupsummary(formal, ...
        ["difficultySection", "axis", "method", "retainedDirections"], ...
        ["mean", "numel"], "correct");
    summary.Properties.VariableNames( ...
        summary.Properties.VariableNames == "mean_correct") = "proportionCorrect";
    summary.Properties.VariableNames( ...
        summary.Properties.VariableNames == "numel_correct") = "trialCount";
    summary.standardError = sqrt(summary.proportionCorrect .* ...
        (1 - summary.proportionCorrect) ./ summary.trialCount);
    summary.ciLower95 = max(0, summary.proportionCorrect - 1.96 .* summary.standardError);
    summary.ciUpper95 = min(1, summary.proportionCorrect + 1.96 .* summary.standardError);
    writetable(summary, fullfile(resultsRoot, "condition_accuracy_summary.csv"));

    figure("Color", "w");
    categories = categorical(summary.method + "_N" + string(summary.retainedDirections));
    errorbar(categories, summary.proportionCorrect, ...
        summary.proportionCorrect - summary.ciLower95, ...
        summary.ciUpper95 - summary.proportionCorrect, "o", "LineWidth", 1.2);
    yline(0.5, "--", "Chance");
    ylabel("Proportion correct");
    xlabel("Method and retained directions");
    ylim([0, 1]);
    grid on;
    exportgraphics(gcf, fullfile(resultsRoot, "condition_accuracy.png"), ...
        "Resolution", 200);

    results.formalTrials = formal;
    results.summary = summary;
    results.thresholds = table();
    results.model = [];
    results.manifestVersion = cfg.manifestVersion;

    if isAdaptive
        adaptive = formal(parse_logical(formal.adaptive), :);
        thresholds = adaptive_thresholds(adaptive);
        results.thresholds = thresholds;
        writetable(thresholds, fullfile(resultsRoot, "adaptive_threshold_summary.csv"));
        figure("Color", "w");
        boxchart(categorical(thresholds.method + "_N" + string(thresholds.retainedDirections)), ...
            thresholds.thresholdDeg);
        ylabel("Adaptive threshold (deg)");
        xlabel("Method and retained directions");
        grid on;
        exportgraphics(gcf, fullfile(resultsRoot, "adaptive_thresholds.png"), ...
            "Resolution", 200);
    end

    modellingRows = isfinite(formal.predictedDPrimeField) & ...
        isfinite(formal.predictedDeltaDPrime) & isfinite(formal.localAIRM) & ...
        isfinite(formal.LSDdB) & isfinite(formal.ILDErrorDb);
    modelData = formal(modellingRows, :);
    if exist("fitglme", "file") == 2 && height(modelData) > 0
        modelData.participantCode = categorical(modelData.participantCode);
        modelData.pairId = categorical(modelData.pairId);
        modelData.axis = categorical(modelData.axis);
        modelData.difficultySection = categorical(modelData.difficultySection);
        results.model = fitglme(modelData, ...
            "correct ~ predictedDPrimeField + predictedDeltaDPrime + localAIRM + LSDdB + ILDErrorDb + difficultySection + axis + (1|participantCode) + (1|pairId)", ...
            "Distribution", "Binomial", "Link", "logit");
        modelText = evalc("disp(results.model)");
        fileId = fopen(fullfile(resultsRoot, "mixed_effects_logistic_model.txt"), "w");
        cleanup = onCleanup(@() fclose(fileId));
        fprintf(fileId, "%s", modelText);
    else
        warning("Mixed-effects model not fitted: Statistics toolbox unavailable or predictors absent.");
    end

    save(fullfile(resultsRoot, "behavioural_analysis_results.mat"), "results");

end

function values = parse_logical(values)
    if islogical(values)
        return;
    elseif isnumeric(values)
        values = values ~= 0;
    else
        text = lower(strtrim(string(values)));
        values = text == "true" | text == "1";
    end
end

function thresholds = adaptive_thresholds(adaptive)
    groups = findgroups(adaptive.participantCode, adaptive.trackId);
    nGroups = max(groups);
    rows = repmat(empty_threshold_row(), nGroups, 1);
    for iGroup = 1:nGroups
        idx = find(groups == iGroup);
        track = sortrows(adaptive(idx, :), "staircaseTrial");
        estimate = track.thresholdEstimateDeg(end);
        if ~isfinite(estimate)
            late = track.separationDeg(max(1, floor(height(track) / 2)):end);
            estimate = median(late, "omitnan");
        end
        first = track(1, :);
        row = empty_threshold_row();
        row.participantCode = first.participantCode;
        row.trackId = first.trackId;
        row.axis = first.axis;
        row.method = first.method;
        row.retainedDirections = first.retainedDirections;
        row.virtualHrtfSubjectId = first.virtualHrtfSubjectId;
        row.thresholdDeg = estimate;
        row.trialCount = height(track);
        row.proportionCorrect = mean(parse_logical(track.correct));
        row.finalReversalCount = max(track.reversalCount, [], "omitnan");
        row.localAIRM = mean(track.localAIRM, "omitnan");
        row.predictedDPrimeReference = mean(track.predictedDPrimeReference, "omitnan");
        row.predictedDPrimeField = mean(track.predictedDPrimeField, "omitnan");
        row.LSDdB = mean(track.LSDdB, "omitnan");
        rows(iGroup, 1) = row;
    end
    thresholds = struct2table(rows);
end

function row = empty_threshold_row()
    row = struct("participantCode", "", "trackId", "", "axis", "", ...
        "method", "", "retainedDirections", NaN, ...
        "virtualHrtfSubjectId", NaN, "thresholdDeg", NaN, ...
        "trialCount", NaN, "proportionCorrect", NaN, ...
        "finalReversalCount", NaN, "localAIRM", NaN, ...
        "predictedDPrimeReference", NaN, "predictedDPrimeField", NaN, ...
        "LSDdB", NaN);
end
