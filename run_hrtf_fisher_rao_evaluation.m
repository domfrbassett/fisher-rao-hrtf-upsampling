%% run_hrtf_fisher_rao_evaluation.m
% Evaluation outline for HRTF spatial upsampling using:
%   - signal-level metrics
%   - AMT Bayesian localisation metrics
%   - Fisher-tensor AIRM discrepancy
%
% Required toolbox adapters:
%   SOFA Toolbox (SOFAload)
%   AMT for Barumerli cue extraction and perceptual-model evaluation
%   SUpDEq and its AKtools / SOFiA / SFS / TriangleRayIntersection
%   dependencies for reconstruction methods
%
% Data convention used below:
%   field.r        : [Ndir x 3] unit Cartesian source directions
%   field.hrtfMag  : [Ndir x Nfreq x 2] linear HRTF magnitudes
%   field.complexHrtf : [Ndir x (Nfreq+1) x 2] one-sided complex HRTFs,
%                    including DC, for SUpDEq
%   field.hrir     : [Ndir x 2 x Nsamples] HRIRs, or [] if unavailable
%   field.fs       : sampling rate in Hz

clear; clc;

%% Configuration

studyRoot = string(fileparts(mfilename("fullpath")));
addpath(char(studyRoot), "-begin");
dependencyRoot = fullfile(studyRoot, "dependencies");
supdeqRoot = fullfile(dependencyRoot, "SUpDEq-master", "SUpDEq-master");

cfg.datasetRoot = fullfile(dependencyRoot, "Sonicom_HRTFs");
cfg.resultsRoot = fullfile(studyRoot, "results", "barumerli_pge_fisher_final");
cfg.sofaFilePattern = "*_FreeFieldCompMinPhase_48kHz.sofa";

datasetRootOverride = string(getenv("FISHERRAO_DATASET_ROOT"));
if strlength(datasetRootOverride) > 0
    cfg.datasetRoot = char(datasetRootOverride);
end
sofaFilePatternOverride = string(getenv("FISHERRAO_SOFA_FILE_PATTERN"));
if strlength(sofaFilePatternOverride) > 0
    cfg.sofaFilePattern = char(sofaFilePatternOverride);
end

cfg.toolbox.sofaRoot = fullfile(dependencyRoot, ...
    "SOFA Toolbox for Matlab and Octave 2.2.0", "SOFAtoolbox");
cfg.toolbox.amtRoot = fullfile(dependencyRoot, ...
    "amtoolbox-full-1.6.0", "amtoolbox-1.6.0");
cfg.toolbox.barumerliCompatibilityRoot = fullfile(studyRoot, ...
    "barumerli_compatibility");
cfg.toolbox.sfsCompatibilityRoot = fullfile(studyRoot, ...
    "sfs_compatibility");
cfg.toolbox.auditoryToolboxRoot = fullfile(dependencyRoot, "AuditoryToolbox");
cfg.toolbox.supdeqRoot = supdeqRoot;
cfg.toolbox.aktoolsRoot = fullfile(supdeqRoot, "thirdParty", "AKtools");
cfg.toolbox.sofiaRoot = fullfile(supdeqRoot, "thirdParty", ...
    "SOFiA R13_MIT-License", "SOFiA");
cfg.toolbox.sfsRoot = fullfile(supdeqRoot, "thirdParty", "sfs-matlab-2.5.0");
cfg.toolbox.triangleRayIntersectionRoot = fullfile(supdeqRoot, ...
    "thirdParty", "TriangleRayIntersection");

% Evaluate the full measured SONICOM cohort. Earlier pilot runs used a
% seeded 41-subject subset; with no external train/test split in the study,
% the full deterministic comparison should use every available subject.
cfg.randomSeed = 0;
cfg.subjectPopulation = 1:203;
cfg.subjectIds = cfg.subjectPopulation;
cfg.validationIds = cfg.subjectIds;
cfg.retentionConditions = [100, 19, 5, 3];
cfg.methods = ["SH", "None_NN", "OBTA_SH", "PC_SH", ...
    "SUpDEq_SH", "SUpDEq_Lim_SH", "SUpDEq_AP_SH", ...
    "SUpDEq_Lim_AP_SH", "SUpDEq_NN", "SUpDEq_MCA", ...
    "SUpDEq_NN_MCA_6dB", "SUpDEq_Bary_MCA_6dB"];

cfg.uniqueDirectionTolerance = 1e-10;
cfg.fpsInitialIndex = [];         % Empty: select initial point from randomSeed
cfg.samplingProvenance = "deterministic FPS substitute held fixed across methods";
cfg.comparatorProtocol.enabled = false;
cfg.comparatorProtocol.path = string(getenv("FISHERRAO_COMPARATOR_PROTOCOL_JSON"));
if strlength(cfg.comparatorProtocol.path) > 0
    cfg.comparatorProtocol.enabled = true;
    cfg = apply_comparator_protocol_config(cfg, studyRoot);
end

methodsOverride = string(getenv("FISHERRAO_METHODS"));
if strlength(methodsOverride) > 0
    cfg.methods = strip(split(methodsOverride, ",")).';
end

resultsNameOverride = string(getenv("FISHERRAO_RESULTS_NAME"));
if strlength(resultsNameOverride) > 0
    cfg.resultsRoot = fullfile(studyRoot, "results", resultsNameOverride);
end
% HRTF / cue processing
cfg.nFreqBins = 256;
cfg.fftLength = 512;
cfg.epsMag = 1e-8;
cfg.window.enabled = false;
cfg.window.lengthSamples = [];    % Set before enabling windowing
cfg.window.fadeLengthSamples = 32;

% Fisher cues use the Barumerli PGE, ILD, and MaxIACCe-transformed ITD
% features. Retain Woodworth timing only for output without recoverable
% interaural timing information.
cfg.fisher.featureSpace = "pge";
cfg.fisher.cueConvention = "barumerli2023_pge_ild_maxiacce";
cfg.itd.mode = "auto";
cfg.itd.fallback = "woodworth";
cfg.headRadius = 0.0875;
cfg.speedOfSound = 343;

% Fisher tensor model
cfg.sigmaMon = 1.25;              % dB, Barumerli PGE cue uncertainty
cfg.sigmaILD = 1.0;               % dB, barumerli2023 model default
cfg.sigmaITD = 0.569;             % transformed ITD scale

cfg.shOrder = 6;
cfg.shRegularisation = 0;         % Use 0 for pinv fitting unless predeclared

% SUpDEq interpolation settings
cfg.supdeq.maxSHOrder = 6;        % Reconstruction cap, independent of Fisher-field smoothing
cfg.supdeq.tikhEps = 0;
cfg.supdeq.publishedMcaDb = Inf; % Setting used in the distributed MCA demo/paper configuration
cfg.supdeq.variantMcDb = 6;      % Limited-boost NN/Bary exploratory variants
cfg.supdeq.limitMC = true;
cfg.supdeq.mcKnee = 0;
cfg.supdeq.mcMinPhase = true;
cfg.supdeq.limFade = "fadeDown";

% AIRM numerical settings
cfg.eta = 1e-6;                   % Fixed SPD regularisation
cfg.eigFloor = 1e-12;             % Roundoff safeguard only
cfg.anisotropyThreshold = 1.10;   % Minimum ratio for orientation reporting
cfg.informationFloor = 1e-10;     % For MAA reporting from unregularised tensor

% Fisher tensors and perceptual-localisation evaluation are deliberately
% separated. The Fisher tensor uses the PGE cue convention above; the
% Barumerli localisation experiment below follows the Hu/LAP-style
% calc_loc.m path: DTF monaural cues, MAP estimation, and the broader
% spectral uncertainty used in that comparator code.
cfg.runPerceptualModel = true;
cfg.perceptual.protocol = "hu_lap_calc_loc";
cfg.perceptual.featureSpace = "dtf";
cfg.perceptual.numExperiments = 300;
perceptualExperimentsOverride = str2double(string( ...
    getenv("FISHERRAO_PERCEPTUAL_NUM_EXPERIMENTS")));
if isfinite(perceptualExperimentsOverride) && perceptualExperimentsOverride >= 1
    cfg.perceptual.numExperiments = round(perceptualExperimentsOverride);
end
cfg.perceptual.methods = cfg.methods;
perceptualMethodsOverride = string(getenv("FISHERRAO_PERCEPTUAL_METHODS"));
if strlength(perceptualMethodsOverride) > 0
    cfg.perceptual.methods = ...
        strip(split(perceptualMethodsOverride, ",")).';
end
cfg.perceptual.retentionConditions = cfg.retentionConditions;
cfg.perceptual.sigmaITD = cfg.sigmaITD;
cfg.perceptual.sigmaILD = cfg.sigmaILD;
cfg.perceptual.sigmaSpectral = 4.0;
cfg.perceptual.sigmaPrior = 11.5;
cfg.perceptual.sigmaMotor = 14.0;
cfg.perceptual.estimator = "MAP";
cfg.perceptual.randomSeed = cfg.randomSeed;
cfg.perceptual.dtfConvention = "log";
cfg.perceptual.experimentsPerBatch = 5; % Bound AMT posterior memory use
% Preserve raw observer errors and additionally report each reconstruction
% relative to the dense measured HRTF evaluated against itself. The signed
% relative metrics are reconstruction minus self-reference performance.
cfg.perceptual.reportRelativeToSelf = true;
cfg.perceptual.plotRelativeToSelf = true;

% Full-run execution: evaluate one row at a time and checkpoint results so
% the long observer-model study can be resumed after interruption.
cfg.execution.streaming = true;
cfg.execution.resume = true;
cfg.execution.checkpointMat = fullfile(cfg.resultsRoot, ...
    "full_evaluation_checkpoint.mat");
cfg.execution.summaryCsv = fullfile(cfg.resultsRoot, ...
    "full_evaluation_summary.csv");
cfg.execution.progressLog = fullfile(cfg.resultsRoot, ...
    "full_evaluation_progress.log");
cfg.execution.writeCheckpointEveryRows = 1;
cfg.execution.tensorRoot = fullfile(cfg.resultsRoot, "metric_tensors");
cfg.execution.subjectSelectionCsv = fullfile(cfg.resultsRoot, ...
    "evaluation_subject_ids.csv");
cfg.execution.perceptualOnly = strcmpi(string( ...
    getenv("FISHERRAO_PERCEPTUAL_ONLY")), "true");
if cfg.execution.perceptualOnly
    assert(cfg.runPerceptualModel, ...
        "Perceptual-only execution requires cfg.runPerceptualModel=true.");
end

% Figures and exported summary tables
cfg.plots.enabled = true;
cfg.plots.visible = "off";
cfg.plots.representativeMethod = "SUpDEq_NN";
cfg.plots.representativeRetention = 3;
cfg.plots.maxEllipseDirections = 55;
cfg.plots.ellipseScale = 1.0;
cfg.plots.maxEllipseRadiusDeg = 20;

rng(cfg.randomSeed);
configure_toolbox_paths(cfg);
verify_configured_dependencies(cfg);

%% Loading of HRTF datasets / folder organisation

if cfg.execution.streaming
    seedCfg = cfg;
    seedCfg.subjectIds = cfg.validationIds(1);
    dataset = load_dense_hrtf_dataset(seedCfg);
    evaluationIndices = 1;
else
    dataset = load_dense_hrtf_dataset(cfg);
    evaluationIndices = select_evaluation_indices(dataset, cfg.validationIds);
end

%% Parsing of HRIRs / windowing and/or equalisation if necessary

dataset = preprocess_hrtf_dataset(dataset, cfg);

%% Initialisation of selected upsampling schemes

upsamplers = initialise_upsampling_methods(cfg);

%% Spatial downsampling through seeded FPS / point elimination

sampling = create_sampling_conditions(dataset, cfg);

if cfg.execution.streaming
    [airmSummary, representative] = run_streaming_evaluation( ...
        dataset, evaluationIndices, upsamplers, sampling, cfg);
    fprintf("Sampling pattern: %s\n", cfg.samplingProvenance);
    disp(airmSummary);

    if cfg.plots.enabled
        plot_metric_relationships(airmSummary, cfg);
        plot_streaming_spatial_fisher_maps(representative, cfg);
        plot_streaming_maa_ellipse_fields(representative, cfg);
        if cfg.runPerceptualModel
            plot_perceptual_metrics(airmSummary, cfg);
        end
    end
    return;
end

%% Perform interpolation for different retention conditions

reconstructions = cell(numel(evaluationIndices), ...
                       numel(cfg.retentionConditions), ...
                       numel(upsamplers));

for iSub = 1:numel(evaluationIndices)

    target = dataset(evaluationIndices(iSub));

    for iCond = 1:numel(cfg.retentionConditions)

        sparseIdx = sampling(iCond).retainedIndices;
        sparseField = subset_spatial_field(target, sparseIdx);

        for iMethod = 1:numel(upsamplers)

            reconstructions{iSub, iCond, iMethod} = ...
                reconstruct_hrtf_field( ...
                    sparseField, target.r, upsamplers(iMethod), cfg);

        end
    end
end

%% Evaluate using standard signal-level metrics

signalResults = struct();

for iSub = 1:numel(evaluationIndices)
    target = dataset(evaluationIndices(iSub));

    for iCond = 1:numel(cfg.retentionConditions)
        for iMethod = 1:numel(upsamplers)

            recon = reconstructions{iSub, iCond, iMethod};

            if recon.isAvailable
                signalResults(iSub, iCond, iMethod).LSD = ...
                    compute_binaural_lsd(target.hrir, recon.hrir, target.fs, cfg);
                signalResults(iSub, iCond, iMethod).ILD = ...
                    compute_ild_error(target.hrir, recon.hrir, cfg);
                signalResults(iSub, iCond, iMethod).status = "completed";
                signalResults(iSub, iCond, iMethod).message = "";
            else
                signalResults(iSub, iCond, iMethod).LSD = NaN;
                signalResults(iSub, iCond, iMethod).ILD = NaN;
                signalResults(iSub, iCond, iMethod).status = "not_applicable";
                signalResults(iSub, iCond, iMethod).message = recon.message;
            end

        end
    end
end

%% Evaluate using perceptual model

perceptualResults = repmat(not_run_perceptual_result( ...
    "not_run", "Perceptual model disabled in configuration."), ...
    numel(evaluationIndices), numel(cfg.retentionConditions), numel(upsamplers));

% Required for Fisher cue extraction as well as observer simulation.
barumerliCompatibilityCleanup = activate_barumerli_compatibility(cfg);

if cfg.runPerceptualModel
    for iSub = 1:numel(evaluationIndices)
        target = dataset(evaluationIndices(iSub));
        referenceTemplate = create_barumerli_template(target, cfg);
        selfReference = not_run_perceptual_result("not_run", ...
            "Self-reference reporting disabled in configuration.");
        if cfg.perceptual.reportRelativeToSelf
            selfReference = evaluate_barumerli_model( ...
                referenceTemplate, target, target, cfg, struct());
        end

        for iCond = 1:numel(cfg.retentionConditions)
            for iMethod = 1:numel(upsamplers)

                recon = reconstructions{iSub, iCond, iMethod};

                if ~is_selected_perceptual_condition( ...
                        upsamplers(iMethod), cfg.retentionConditions(iCond), cfg)
                    perceptualResults(iSub, iCond, iMethod) = ...
                        not_run_perceptual_result("not_selected", ...
                        "Not included in declared Barumerli shortlist.");
                elseif ~recon.isAvailable
                    perceptualResults(iSub, iCond, iMethod) = ...
                        not_run_perceptual_result("not_applicable", recon.message);
                else
                    perceptualResults(iSub, iCond, iMethod) = ...
                        evaluate_barumerli_model(referenceTemplate, target, recon, cfg);
                end
                perceptualResults(iSub, iCond, iMethod) = ...
                    attach_self_reference_metrics( ...
                        perceptualResults(iSub, iCond, iMethod), ...
                        selfReference, cfg);

            end
        end
    end
end

%% Now evaluate using AIRM distance and the Fisher-Rao family

fisherResults = struct();

for iSub = 1:numel(evaluationIndices)

    target = dataset(evaluationIndices(iSub));

    for iCond = 1:numel(cfg.retentionConditions)
        for iMethod = 1:numel(upsamplers)

            recon = reconstructions{iSub, iCond, iMethod};

            if recon.isAvailable
                fisherResult = evaluate_fisher_tensor_airm(target, recon, cfg);
            else
                fisherResult = unavailable_fisher_result(size(target.r, 1), ...
                    recon.message, cfg);
            end

            if iSub == 1 && iCond == 1 && iMethod == 1
                fisherResults = fisherResult;
            else
                fisherResults(iSub, iCond, iMethod) = fisherResult;
            end

        end
    end
end

%% Aggregate and report results

airmSummary = build_airm_summary_table( ...
    dataset, evaluationIndices, upsamplers, sampling, reconstructions, ...
    signalResults, fisherResults, perceptualResults);

fprintf("Sampling pattern: %s\n", cfg.samplingProvenance);
disp(airmSummary);

if cfg.plots.enabled
    ensure_results_folder(cfg.resultsRoot);
    writetable(airmSummary, fullfile(cfg.resultsRoot, "evaluation_summary.csv"));
    plot_metric_relationships(airmSummary, cfg);
    plot_spatial_fisher_maps(dataset, evaluationIndices, upsamplers, ...
        sampling, fisherResults, cfg);
    plot_maa_ellipse_fields(dataset, evaluationIndices, upsamplers, ...
        sampling, fisherResults, cfg);
    if cfg.runPerceptualModel
        plot_perceptual_metrics(airmSummary, cfg);
    end
end

function [summary, representative] = run_streaming_evaluation( ...
        seedDataset, ~, upsamplers, sampling, cfg)
% Evaluate one subject/method/condition row at a time and checkpoint output.

    ensure_results_folder(cfg.resultsRoot);
    ensure_results_folder(cfg.execution.tensorRoot);
    evaluationSubjectIds = table(cfg.validationIds(:), ...
        'VariableNames', {'subjectId'});
    writetable(evaluationSubjectIds, cfg.execution.subjectSelectionCsv);
    summary = table();
    representative = struct();

    if cfg.execution.resume && isfile(cfg.execution.checkpointMat)
        checkpoint = load(cfg.execution.checkpointMat, ...
            "checkpointSummary", "checkpointRepresentative");
        if isfield(checkpoint, "checkpointSummary")
            summary = checkpoint.checkpointSummary;
        end
        if isfield(checkpoint, "checkpointRepresentative")
            representative = checkpoint.checkpointRepresentative;
        end
    end
    summary = add_perceptual_reference_columns(summary);
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
                write_streaming_checkpoint(summary, representative, cfg);
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
                        write_streaming_checkpoint( ...
                            summary, representative, cfg);
                    end
                    continue;
                end

                signal = evaluate_signal_metrics(target, recon, cfg);
                if recon.isAvailable
                    [fisher, reconstructedFeatures, targetCueCache] = ...
                        evaluate_fisher_tensor_airm( ...
                            target, recon, cfg, targetCueCache);
                else
                    fisher = unavailable_fisher_result(size(target.r, 1), ...
                        recon.message, cfg);
                    reconstructedFeatures = struct();
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

                if target.subjectId == cfg.validationIds(1) && ...
                        method.name == cfg.plots.representativeMethod && ...
                        sampling(iCondition).retentionCount == ...
                        cfg.plots.representativeRetention
                    representative.target = target;
                    representative.result = fisher;
                    representative.methodName = method.name;
                    representative.retentionCount = ...
                        sampling(iCondition).retentionCount;
                end

                completedRows = completedRows + 1;
                completedKeys(end + 1, 1) = rowKey; %#ok<AGROW>
                if mod(completedRows, ...
                        cfg.execution.writeCheckpointEveryRows) == 0
                    write_streaming_checkpoint(summary, representative, cfg);
                end
            end
        end
    end

    write_streaming_checkpoint(summary, representative, cfg);
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

function signal = evaluate_signal_metrics(target, recon, cfg)

    if recon.isAvailable
        signal.LSD = compute_binaural_lsd(target.hrir, recon.hrir, target.fs, cfg);
        signal.ILD = compute_ild_error(target.hrir, recon.hrir, cfg);
        signal.status = "completed";
        signal.message = "";
    else
        signal.LSD = NaN;
        signal.ILD = NaN;
        signal.status = "not_applicable";
        signal.message = recon.message;
    end

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

function write_streaming_checkpoint(summary, representative, cfg)

    checkpointSummary = summary;
    checkpointRepresentative = representative;
    save(cfg.execution.checkpointMat, "checkpointSummary", ...
        "checkpointRepresentative", "-v7.3");
    writetable(summary, cfg.execution.summaryCsv);

end

function append_progress_log(cfg, message)

    fileId = fopen(cfg.execution.progressLog, "a");
    assert(fileId ~= -1, "Unable to open progress log: %s", ...
        cfg.execution.progressLog);
    fileCleanup = onCleanup(@() fclose(fileId));
    fprintf(fileId, "[%s] %s\n", char(datetime("now")), message);

end

function write_metric_tensor_files(target, method, samplingCondition, fisher, cfg)
% Save the measured tensor once and one reconstruction tensor per test row.

    subjectFolder = fullfile(cfg.execution.tensorRoot, ...
        sprintf("subject_%04d", target.subjectId));
    ensure_results_folder(subjectFolder);

    if fisher.status == "completed"
        referencePath = fullfile(subjectFolder, "reference_metric_tensor.mat");
        if ~isfile(referencePath)
            subjectId = target.subjectId;
            sourceFile = target.filePath;
            coordinatesCartesian = target.r;
            coordinatesAzimuthElevationDeg = target.azElDeg;
            metricTensor = fisher.targetTensor;
            itdMode = fisher.targetITDMode;
            cueExtractionMode = fisher.cueExtractionMode;
            status = "completed";
            save(referencePath, "subjectId", "sourceFile", ...
                "coordinatesCartesian", "coordinatesAzimuthElevationDeg", ...
                "metricTensor", "itdMode", "cueExtractionMode", "status", "-v7.3");
        end
    end

    methodFileName = regexprep(char(method.name), "[^A-Za-z0-9_]", "_");
    reconstructionPath = fullfile(subjectFolder, sprintf( ...
        "%s_N%03d_metric_tensor.mat", methodFileName, ...
        samplingCondition.retentionCount));
    subjectId = target.subjectId;
    sourceFile = target.filePath;
    methodName = method.name;
    retainedDirections = samplingCondition.retentionCount;
    coordinatesCartesian = target.r;
    coordinatesAzimuthElevationDeg = target.azElDeg;
    metricTensor = fisher.reconstructedTensor;
    itdMode = fisher.reconstructedITDMode;
    cueExtractionMode = fisher.cueExtractionMode;
    status = fisher.status;
    message = fisher.message;
    save(reconstructionPath, "subjectId", "sourceFile", "methodName", ...
        "retainedDirections", "coordinatesCartesian", ...
        "coordinatesAzimuthElevationDeg", "metricTensor", "itdMode", ...
        "cueExtractionMode", "status", "message", "-v7.3");

end

function [result, reconstructedFeatures, targetCueCache] = ...
    evaluate_fisher_tensor_airm(target, recon, cfg, targetCueCache)
% Evaluate reference and reconstructed HRTFs through their local
% Fisher information tensors and the AIRM distance.
%
% target and recon must be defined on the same unique physical grid.

    if nargin < 4
        targetCueCache = struct();
    end

    assert(isequal(size(target.r), size(recon.r)), ...
        "Target and reconstruction direction grids must match.");

    r = target.r;
    nDir = size(r, 1);

    %% Extract cue samples at measured directions

    if ~isfield(targetCueCache, "q")
        [targetCueCache.q, targetCueCache.itdMode] = ...
            extract_fisher_cues(target, target, cfg);
    end
    qTarget = targetCueCache.q;
    targetITDMode = targetCueCache.itdMode;
    [qRecon, reconstructedITDMode, reconstructedFeatures] = ...
        extract_fisher_cues(recon, target, cfg);

    assert(size(qTarget, 1) == nDir);
    assert(isequal(size(qTarget), size(qRecon)));

    %% Fit smooth spherical-harmonic cue fields

    shTarget = fit_sh_cue_field(r, qTarget, cfg);
    shRecon  = fit_sh_cue_field(r, qRecon,  cfg);

    %% Define cue-noise precision matrix

    nMonauralFeatures = size(qTarget, 2) - 2;
    assert(nMonauralFeatures >= 1, ...
        "Barumerli PGE extraction returned no monaural cue features.");

    sigma = [ ...
        repmat(cfg.sigmaMon, 1, nMonauralFeatures), ...
        cfg.sigmaILD, ...
        cfg.sigmaITD ...
    ];

    precision = diag(1 ./ (sigma .^ 2));

    %% Construct tangent-plane Fisher tensors

    gTarget = zeros(2, 2, nDir);
    gRecon  = zeros(2, 2, nDir);
    % Pole-stable analytical Cartesian SH gradients, as specified in the
    % methodology before projection onto a local tangent basis.
    [~, dYdx, dYdy, dYdz] = real_sh_basis_cartesian(r, cfg.shOrder);

    for n = 1:nDir

        rn = r(n, :).';
        V = local_tangent_basis(rn);
        JYCart = [dYdx(n, :).', dYdy(n, :).', dYdz(n, :).'];

        JCartTarget = shTarget.coefficients.' * JYCart;
        JCartRecon  = shRecon.coefficients.' * JYCart;

        JTarget = JCartTarget * V;
        JRecon  = JCartRecon * V;

        gTarget(:, :, n) = JTarget.' * precision * JTarget;
        gRecon(:, :, n)  = JRecon.'  * precision * JRecon;

        gTarget(:, :, n) = symmetrise(gTarget(:, :, n));
        gRecon(:, :, n)  = symmetrise(gRecon(:, :, n));

    end

    %% Compare tensor fields using regularised AIRM

    airm = zeros(nDir, 1);
    determinantError = zeros(nDir, 1);
    anisotropyError = zeros(nDir, 1);
    orientationError = nan(nDir, 1);

    targetMAA = nan(nDir, 2);
    reconMAA = nan(nDir, 2);

    for n = 1:nDir

        G = gTarget(:, :, n);
        Ghat = gRecon(:, :, n);

        Geta = G + cfg.eta * eye(2);
        GhatEta = Ghat + cfg.eta * eye(2);

        [airm(n), determinantError(n), anisotropyError(n), ...
            orientationError(n)] = compare_spd_tensors( ...
                Geta, GhatEta, cfg);

        targetMAA(n, :) = principal_axis_maa(G, cfg);
        reconMAA(n, :)  = principal_axis_maa(Ghat, cfg);

    end

    %% Summarise endpoints

    result.meanAIRM = mean(airm);
    result.medianAIRM = median(airm);
    result.stdAIRM = std(airm);
    result.iqrAIRM = iqr(airm);
    result.airmByDirection = airm;

    result.meanDeterminantError = mean(determinantError);
    result.determinantErrorByDirection = determinantError;

    result.meanAnisotropyError = mean(anisotropyError);
    result.anisotropyErrorByDirection = anisotropyError;

    validOrientation = ~isnan(orientationError);
    result.orientationErrorByDirection = orientationError;
    result.orientationValidCount = sum(validOrientation);
    result.orientationValidProportion = result.orientationValidCount / nDir;

    if any(validOrientation)
        result.meanOrientationErrorRad = mean(orientationError(validOrientation));
        result.meanOrientationErrorDeg = ...
            rad2deg(result.meanOrientationErrorRad);
    else
        result.meanOrientationErrorRad = NaN;
        result.meanOrientationErrorDeg = NaN;
    end

    result.targetTensor = gTarget;
    result.reconstructedTensor = gRecon;

    % Model-based local MAA values along each tensor's principal axes.
    result.targetPrincipalMAA = targetMAA;
    result.reconstructedPrincipalMAA = reconMAA;
    result.targetITDMode = targetITDMode;
    result.reconstructedITDMode = reconstructedITDMode;
    result.cueExtractionMode = cfg.fisher.cueConvention;
    result.status = "completed";
    result.message = "";

end

function [q, itdMode, features] = extract_fisher_cues(field, layoutField, cfg)
% Construct the deterministic Fisher cue vector with the Barumerli feature
% extractor: [PGE_left, PGE_right, ILD, transformed_ITD].

    assert(cfg.fisher.featureSpace == "pge", ...
        "The Fisher implementation requires Barumerli PGE features.");
    featureField = supply_barumerli_feature_hrir(field, cfg);
    featureDtf = convert_field_to_dtf_sofa(featureField, layoutField, cfg);
    features = barumerli2023_featureextraction(featureDtf, ...
        'target', char(cfg.fisher.featureSpace));
    assert_barumerli_target_coordinates(features, layoutField.r, ...
        cfg.uniqueDirectionTolerance);

    monaural = double(features.monaural);
    ild = double(features.ild);

    assert(cfg.itd.mode == "auto", "Unknown cfg.itd.mode.");
    if supports_physical_itd(field)
        itd = double(features.itd);
        itdMode = "barumerli_maxiacce";
    else
        assert(cfg.itd.fallback == "woodworth", "Unknown ITD fallback.");
        itd = transform_itd(woodworth_itd(field.r, cfg));
        itdMode = "woodworth_fallback";
        features.itd = itd;
    end

    q = [monaural, ild, itd];

end

function featureField = supply_barumerli_feature_hrir(field, cfg)
% Barumerli extracts spectral and ILD features from HRIRs. For a future
% magnitude-only reconstruction, construct a zero-phase HRIR only to make
% those magnitude-derived features available. Its artificial timing is
% never used: supports_physical_itd(field) remains false and ITD is
% replaced by the declared Woodworth fallback.

    featureField = field;
    if isfield(field, "hrir") && ~isempty(field.hrir)
        return;
    end

    assert(isfield(field, "hrtfMag") && ~isempty(field.hrtfMag), ...
        "Magnitude-only output must provide hrtfMag for Barumerli features.");
    oneSidedMagnitude = cat(2, field.hrtfMag(:, 1, :), field.hrtfMag);
    twoSidedMagnitude = cat(2, oneSidedMagnitude, ...
        oneSidedMagnitude(:, end - 1:-1:2, :));
    featureHrir = real(ifft(twoSidedMagnitude, cfg.fftLength, 2));
    featureField.hrir = permute(featureHrir, [1, 3, 2]);
    featureField.hasInterauralDelay = false;
    featureField.itdProvenance = "woodworth_fallback_from_magnitude_only_output";

end

function tau = woodworth_itd(r, cfg)

    % SOFA Cartesian +y is left. AMT MaxIACCe uses xcorr(left,right),
    % whose ITD is negative for a left-leading source; keep the analytic
    % fallback in that same feature convention.
    theta = -asin(r(:, 2));

    tau = (cfg.headRadius / cfg.speedOfSound) .* ...
        (theta + sin(theta));

end

function available = supports_physical_itd(field)

    available = isfield(field, "hasInterauralDelay") && ...
        field.hasInterauralDelay && ~isempty(field.hrir);

end

function assert_barumerli_target_coordinates(features, expectedR, tolerance)
% Fail if AMT target features no longer preserve the physical grid ordering.

    assert(isfield(features, "coords") && ~isempty(features.coords), ...
        "Barumerli target features do not contain source coordinates.");
    featureR = double(features.coords.return_positions('cartesian'));
    featureR = featureR ./ vecnorm(featureR, 2, 2);
    expectedR = expectedR ./ vecnorm(expectedR, 2, 2);
    assert(isequal(size(featureR), size(expectedR)), ...
        "Barumerli target feature coordinates do not match the reference grid.");
    maximumDifference = max(abs(featureR - expectedR), [], "all");
    assert(maximumDifference <= max(10 * tolerance, 1e-9), ...
        "Barumerli target feature coordinates do not match the reference grid.");

end

function itd = transform_itd(tau)

    itd = sign(tau) .* ...
        (log(32.5e-6 + 0.095 .* abs(tau)) - log(32.5e-6)) ...
        ./ 0.095;

end

function model = fit_sh_cue_field(r, q, cfg)
% Fit each cue feature as a smooth real spherical-harmonic field.

    Y = real_sh_basis_cartesian(r, cfg.shOrder);

    if cfg.shRegularisation == 0
        coefficients = pinv(Y) * q;
    else
        lambda = cfg.shRegularisation;
        coefficients = ...
            (Y.' * Y + lambda * eye(size(Y, 2))) \ (Y.' * q);
    end

    model.coefficients = coefficients;
    model.order = cfg.shOrder;

end

function V = local_tangent_basis(r)

    if abs(r(3)) > 0.9
        auxiliary = [0; 1; 0];
    else
        auxiliary = [0; 0; 1];
    end

    u1 = cross(auxiliary, r);
    u1 = u1 / norm(u1);

    u2 = cross(r, u1);
    u2 = u2 / norm(u2);

    V = [u1, u2];

end

function [dAIRM, detError, anisError, orientError] = ...
    compare_spd_tensors(G, Ghat, cfg)

    G = symmetrise(G);
    Ghat = symmetrise(Ghat);

    %% AIRM distance using Cholesky congruence

    L = chol(G, "lower");

    S = L \ (Ghat / L.');
    S = symmetrise(S);

    lambda = eig(S);
    lambda = max(lambda, cfg.eigFloor);

    dAIRM = sqrt(sum(log(lambda) .^ 2));

    %% Scale difference

    detError = abs(log(det(Ghat) / det(G)));

    %% Anisotropy and orientation

    [V, mu] = eig(G, "vector");
    [Vhat, muHat] = eig(Ghat, "vector");

    [mu, order] = sort(mu, "descend");
    V = V(:, order);

    [muHat, orderHat] = sort(muHat, "descend");
    Vhat = Vhat(:, orderHat);

    ratio = mu(1) / mu(2);
    ratioHat = muHat(1) / muHat(2);

    anisError = abs(log(ratioHat / ratio));

    if ratio >= cfg.anisotropyThreshold && ...
            ratioHat >= cfg.anisotropyThreshold

        dotProduct = abs(V(:, 1).' * Vhat(:, 1));
        dotProduct = min(max(dotProduct, 0), 1);

        orientError = acos(dotProduct);

    else
        orientError = NaN;
    end

end

function maa = principal_axis_maa(G, cfg)
% Model-based local MAA along the principal axes of the unregularised
% Fisher tensor. Values are reported only where the tensor is informative
% in both tangent directions.

    G = symmetrise(G);

    mu = eig(G);
    mu = sort(mu, "descend");

    if min(mu) <= cfg.informationFloor
        maa = [NaN, NaN];
        return;
    end

    maa = 1 ./ sqrt(mu).';

end

function A = symmetrise(A)

    A = 0.5 * (A + A.');

end

function configure_toolbox_paths(cfg)
% Add the installed toolboxes without recursively adding SUpDEq's bundled
% copies of SOFA and AMT; the explicit project-local versions remain the
% selected versions for data loading and optional observer evaluation.

    configuredNames = ["sofaRoot", "amtRoot", "auditoryToolboxRoot", ...
        "supdeqRoot", "aktoolsRoot", "sofiaRoot", "sfsRoot", ...
        "triangleRayIntersectionRoot", "sfsCompatibilityRoot"];

    for iToolbox = 1:numel(configuredNames)
        toolboxPath = string(cfg.toolbox.(configuredNames(iToolbox)));
        assert(isfolder(toolboxPath), ...
            "Configured dependency folder does not exist: %s", toolboxPath);
    end

    addpath(genpath(char(cfg.toolbox.auditoryToolboxRoot)));

    addpath(char(cfg.toolbox.amtRoot));
    if exist("amt_start", "file") == 2
        amt_start('localonly', 'silent');
    end

    % Make the declared SUpDEq dependencies and SOFA version authoritative
    % after AMT initialises its own optional bundled toolboxes.
    addpath(char(cfg.toolbox.supdeqRoot));
    addpath(genpath(char(cfg.toolbox.aktoolsRoot)));
    addpath(genpath(char(cfg.toolbox.sofiaRoot)));
    addpath(genpath(char(cfg.toolbox.sfsRoot)));
    addpath(genpath(char(cfg.toolbox.triangleRayIntersectionRoot)));
    addpath(genpath(char(cfg.toolbox.sofaRoot)));
    % Shadow only the current-MATLAB-incompatible SFS helper. The external
    % SUpDEq repository remains unmodified.
    addpath(char(cfg.toolbox.sfsCompatibilityRoot), "-begin");
    clear findvoronoi;
    assert(startsWith(string(which("findvoronoi")), ...
        string(cfg.toolbox.sfsCompatibilityRoot)), ...
        "Project-local SFS compatibility override is not active.");
    remove_legacy_rms_shadow_paths;

end

function remove_legacy_rms_shadow_paths
% SFS and LTFAT bundle older rms.m variants that do not accept MATLAB's
% rms(...,'dim',n) call used by AMT barumerli2023_featureextraction.

    pathEntries = string(strsplit(path, pathsep));
    lowerEntries = lower(pathEntries);
    shadowsRms = contains(lowerEntries, "sfs_octave") | ...
        (contains(lowerEntries, "ltfat") & endsWith(lowerEntries, "sigproc"));
    pathsToRemove = unique(pathEntries(shadowsRms));

    for iPath = 1:numel(pathsToRemove)
        if contains(string(path), pathsToRemove(iPath))
            rmpath(char(pathsToRemove(iPath)));
        end
    end

    selectedRms = lower(string(which("rms")));
    assert(~contains(selectedRms, "sfs_octave") && ...
        ~contains(selectedRms, "ltfat"), ...
        "A legacy toolbox rms.m still shadows MATLAB rms: %s", selectedRms);

end

function cleanup = activate_barumerli_compatibility(cfg)
% Activate local API compatibility adapters only while AMT evaluation is
% enabled; the AMT installation itself remains unmodified.

    root = string(cfg.toolbox.barumerliCompatibilityRoot);
    assert(isfolder(root), "Missing AMT compatibility adapter folder: %s", root);
    addpath(char(root), "-begin");
    clear rms;
    cleanup = onCleanup(@() deactivate_barumerli_compatibility(root));

end

function deactivate_barumerli_compatibility(root)

    if contains(string(path), root)
        rmpath(char(root));
    end
    clear rms;

end

function verify_configured_dependencies(cfg)
% Fail early with a precise message if the installed toolboxes are moved
% or an expected SUpDEq support function is absent.

    assert(isfolder(cfg.datasetRoot), ...
        "The SONICOM dataset folder does not exist: %s", cfg.datasetRoot);

    requiredFunctions = ["SOFAload", "supdeq_interpHRTF", "AKsht", ...
        "AKonsetDetect", "sofia_itc", "SFS_start", "TriangleRayIntersection", ...
        "ERBFilterBank"];

    for iFunction = 1:numel(requiredFunctions)
        assert(exist(requiredFunctions(iFunction), "file") ~= 0, ...
            "Required dependency function is unavailable: %s", ...
            requiredFunctions(iFunction));
    end

    requiredFisherFeatureFunctions = ["amt_start", "SOFAhrtf2dtf", ...
        "barumerli2023_featureextraction"];
    for iFunction = 1:numel(requiredFisherFeatureFunctions)
        assert(exist(requiredFisherFeatureFunctions(iFunction), "file") ~= 0, ...
            "Barumerli Fisher-feature dependency is unavailable: %s", ...
            requiredFisherFeatureFunctions(iFunction));
    end

    if cfg.runPerceptualModel
        requiredPerceptualFunctions = ["barumerli2023", "barumerli2023_metrics"];
        for iFunction = 1:numel(requiredPerceptualFunctions)
            assert(exist(requiredPerceptualFunctions(iFunction), "file") ~= 0, ...
                "Perceptual dependency function is unavailable: %s", ...
                requiredPerceptualFunctions(iFunction));
        end
    end

end

function dataset = load_dense_hrtf_dataset(cfg)
% Load measured HRIR sets from SOFA files. The loader deliberately keeps
% measured HRIRs and Cartesian locations together: later interpolation is
% evaluated on the full measured direction grid.

    assert(~startsWith(string(cfg.datasetRoot), "PATH_TO_"), ...
        "Set cfg.datasetRoot to the directory containing the SOFA files.");
    assert(isfolder(cfg.datasetRoot), ...
        "The configured dataset directory does not exist: %s", cfg.datasetRoot);
    assert(exist("SOFAload", "file") == 2, ...
        "SOFAload was not found. Set cfg.toolbox.sofaRoot to a SOFA Toolbox installation.");

    files = dir(fullfile(char(cfg.datasetRoot), "**", char(cfg.sofaFilePattern)));
    assert(~isempty(files), ...
        "No SOFA files matching %s were found beneath %s.", ...
        cfg.sofaFilePattern, cfg.datasetRoot);

    dataset = struct([]);

    for iFile = 1:numel(files)

        filePath = string(fullfile(files(iFile).folder, files(iFile).name));
        subjectId = parse_subject_id(files(iFile).name);

        if ~isempty(cfg.subjectIds) && ...
                (isnan(subjectId) || ~ismember(subjectId, cfg.subjectIds))
            continue;
        end

        field = read_sofa_hrtf_field(filePath, cfg);
        field.subjectId = subjectId;
        field.filePath = filePath;

        if isempty(dataset)
            dataset = field;
        else
            dataset(end + 1) = field; %#ok<AGROW>
        end

    end

    assert(~isempty(dataset), ...
        "No SOFA files remained after applying cfg.subjectIds.");

end

function subjectId = parse_subject_id(fileName)
% SONICOM names begin P0001, P0002, and so forth. Do not infer the subject
% from a later acquisition-rate token such as the 48 in "_48kHz".

    token = regexp(fileName, "^P(\d+)", "tokens", "once");

    if isempty(token)
        subjectId = NaN;
    else
        subjectId = str2double(token{1});
    end

end

function field = read_sofa_hrtf_field(filePath, cfg)
% Read one SimpleFreeFieldHRIR-like SOFA object through the SOFA Toolbox.

    sofa = SOFAload(char(filePath));

    assert(isfield(sofa, "Data") && isfield(sofa.Data, "IR"), ...
        "SOFA file does not contain Data.IR: %s", filePath);
    assert(isfield(sofa.Data, "SamplingRate"), ...
        "SOFA file does not contain Data.SamplingRate: %s", filePath);
    assert(isfield(sofa, "SourcePosition"), ...
        "SOFA file does not contain SourcePosition: %s", filePath);

    hrir = double(sofa.Data.IR);
    fs = double(sofa.Data.SamplingRate(1));

    assert(ndims(hrir) == 3 && size(hrir, 2) >= 2, ...
        "Expected Data.IR in [directions x receivers x samples] form.");
    hrir = hrir(:, 1:2, :);

    [r, azElDeg] = convert_sofa_positions(sofa);
    assert(size(hrir, 1) == size(r, 1), ...
        "SOFA HRIR count and SourcePosition count disagree in %s.", filePath);

    retained = unique_direction_indices(r, cfg.uniqueDirectionTolerance);

    field.r = r(retained, :);
    field.azElDeg = azElDeg(retained, :);
    field.hrir = hrir(retained, :, :);
    field.fs = fs;
    field.hasInterauralDelay = true;
    field.itdProvenance = "measured_hrir";
    if isfield(sofa.Data, "Delay") && ...
            size(sofa.Data.Delay, 1) == size(hrir, 1) && ...
            any(abs(double(sofa.Data.Delay(:))) > eps)
        delay = double(sofa.Data.Delay);
        field.hrir = incorporate_sofa_delay(field.hrir, ...
            delay(retained, :), fs);
        sofa.Data.Delay(:) = 0;
        field.itdProvenance = "hrir_with_sofa_delay_incorporated";
    end
    sofa.Data.IR = field.hrir;
    sofa.SourcePosition = sofa.SourcePosition(retained, :);
    if isfield(sofa.Data, "Delay") && ...
            size(sofa.Data.Delay, 1) == size(hrir, 1)
        sofa.Data.Delay = sofa.Data.Delay(retained, :);
    end
    field.sofaObject = SOFAupdateDimensions(sofa);

end

function hrir = incorporate_sofa_delay(hrir, delay, fs)
% Apply SOFA Data.Delay to HRIR samples once. External comparator exports
% may store delay in samples; very small fractional values are interpreted
% as seconds.
 
    delay = double(delay);
    if max(abs(delay(:))) < 1e-2 && any(abs(delay(:)) > eps)
        delaySamples = round(delay * fs);
    else
        delaySamples = round(delay);
    end
 
    nSamples = size(hrir, 3);
    nEars = min(size(hrir, 2), size(delaySamples, 2));
 
    for iDirection = 1:size(hrir, 1)
        for iEar = 1:nEars
            shift = delaySamples(iDirection, iEar);
            if shift > 0
                shift = min(shift, nSamples);
                hrir(iDirection, iEar, :) = cat(3, ...
                    zeros(1, 1, shift, "like", hrir), ...
                    hrir(iDirection, iEar, 1:(nSamples-shift)));
            elseif shift < 0
                shift = min(abs(shift), nSamples);
                hrir(iDirection, iEar, :) = cat(3, ...
                    hrir(iDirection, iEar, (shift+1):nSamples), ...
                    zeros(1, 1, shift, "like", hrir));
            end
        end
    end
 
end

function [r, azElDeg] = convert_sofa_positions(sofa)
% Return internal Cartesian directions and conventional azimuth/elevation.
% SUpDEq conversion to its polar-elevation convention is handled separately.

    positions = double(sofa.SourcePosition);
    positionType = "spherical";
    positionUnits = "degree";

    if isfield(sofa, "SourcePosition_Type")
        positionType = lower(string(sofa.SourcePosition_Type));
    end
    if isfield(sofa, "SourcePosition_Units")
        positionUnits = lower(string(sofa.SourcePosition_Units));
    end

    if contains(positionType, "spherical")

        azElDeg = positions(:, 1:2);

        if contains(positionUnits, "radian")
            azElDeg = rad2deg(azElDeg);
        end

        [x, y, z] = sph2cart(deg2rad(azElDeg(:, 1)), ...
            deg2rad(azElDeg(:, 2)), ones(size(azElDeg, 1), 1));
        r = [x, y, z];

    elseif contains(positionType, "cartesian")

        r = positions(:, 1:3);
        r = r ./ vecnorm(r, 2, 2);
        [az, el, ~] = cart2sph(r(:, 1), r(:, 2), r(:, 3));
        azElDeg = rad2deg([az, el]);

    else
        error("Unsupported SOFA SourcePosition_Type: %s", positionType);
    end

    r = r ./ vecnorm(r, 2, 2);

end

function retained = unique_direction_indices(r, tolerance)
% Suppress duplicate physical positions before fitting or interpolation.

    assert(tolerance > 0, "cfg.uniqueDirectionTolerance must be positive.");
    directionKey = round(r / tolerance);
    [~, retained] = unique(directionKey, "rows", "stable");
    retained = sort(retained);

end

function evaluationIndices = select_evaluation_indices(dataset, validationIds)

    if isempty(validationIds)
        evaluationIndices = 1:numel(dataset);
        return;
    end

    loadedIds = [dataset.subjectId];
    evaluationIndices = zeros(1, numel(validationIds));

    for iId = 1:numel(validationIds)
        match = find(loadedIds == validationIds(iId), 1, "first");
        assert(~isempty(match), ...
            "Requested validation subject %g was not loaded.", validationIds(iId));
        evaluationIndices(iId) = match;
    end

end

function dataset = preprocess_hrtf_dataset(dataset, cfg)
% Apply an optional terminal fade/window and form spectra used by both the
% SUpDEq adapter and the subsequent signal/Fisher evaluations.

    for iSubject = 1:numel(dataset)

        if cfg.window.enabled

            nSamples = size(dataset(iSubject).hrir, 3);
            nKeep = cfg.window.lengthSamples;
            assert(~isempty(nKeep) && nKeep >= 2 && nKeep <= nSamples, ...
                "Set cfg.window.lengthSamples within the available HRIR length.");

            hrir = dataset(iSubject).hrir(:, :, 1:nKeep);
            nFade = min(cfg.window.fadeLengthSamples, nKeep);
            tail = 0.5 * (1 + cos(linspace(0, pi, nFade)));
            hrir(:, :, end - nFade + 1:end) = ...
                hrir(:, :, end - nFade + 1:end) .* ...
                reshape(tail, 1, 1, []);

            dataset(iSubject).hrir = hrir;

        end

        processedField = refresh_field_spectra(dataset(iSubject), cfg);
        dataset(iSubject).complexHrtf = processedField.complexHrtf;
        dataset(iSubject).hrtfMag = processedField.hrtfMag;
        dataset(iSubject).freqHzWithDC = processedField.freqHzWithDC;
        dataset(iSubject).freqHz = processedField.freqHz;

    end

end

function field = refresh_field_spectra(field, cfg)
 
    field.hrir = real(field.hrir);
    nSamples = size(field.hrir, 3);
    minimumFftLength = max(nSamples, 2 * cfg.nFreqBins);
    if isempty(cfg.fftLength)
        fftLength = 2^nextpow2(minimumFftLength);
    else
        fftLength = cfg.fftLength;
    end
 
    assert(fftLength >= nSamples, ...
        "cfg.fftLength must be at least as long as the processed HRIR.");
    assert(fftLength >= 2 * cfg.nFreqBins, ...
        "cfg.fftLength must provide at least cfg.nFreqBins one-sided non-DC bins.");
 
    spectrum = fft(field.hrir, fftLength, 3);
    spectrum = spectrum(:, :, 1:(cfg.nFreqBins + 1));

    field.fftLength = fftLength;
    field.complexHrtf = permute(spectrum, [1, 3, 2]);
    field.hrtfMag = abs(field.complexHrtf(:, 2:end, :));
    field.freqHzWithDC = (0:cfg.nFreqBins) * (field.fs / fftLength);
    field.freqHz = field.freqHzWithDC(2:end);

end

function upsamplers = initialise_upsampling_methods(cfg)
% Encode published preprocessing comparisons, published SUpDEq/MCA, and
% explicit interpolation variants. The distributed MCA demo defines MCA
% as SUpDEq preprocessing, SH interpolation, and magnitude correction with
% unlimited boost.

    upsamplers = repmat(struct( ...
        "name", "", "preprocessing", "", "interpolation", "", ...
        "magnitudeCorrectionDb", NaN, "externalRoot", ""), ...
        1, numel(cfg.methods));

    for iMethod = 1:numel(cfg.methods)

        methodName = string(cfg.methods(iMethod));
        upsamplers(iMethod).name = methodName;

        switch methodName
            case "SH"
                upsamplers(iMethod).preprocessing = "None";
                upsamplers(iMethod).interpolation = "SH";
            case "None_NN"
                upsamplers(iMethod).preprocessing = "None";
                upsamplers(iMethod).interpolation = "NN";
            case "OBTA_SH"
                upsamplers(iMethod).preprocessing = "OBTA";
                upsamplers(iMethod).interpolation = "SH";
            case "PC_SH"
                upsamplers(iMethod).preprocessing = "PC";
                upsamplers(iMethod).interpolation = "SH";
            case "SUpDEq_SH"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "SH";
            case "SUpDEq_Lim_SH"
                upsamplers(iMethod).preprocessing = "SUpDEq_Lim";
                upsamplers(iMethod).interpolation = "SH";
            case "SUpDEq_AP_SH"
                upsamplers(iMethod).preprocessing = "SUpDEq_AP";
                upsamplers(iMethod).interpolation = "SH";
            case "SUpDEq_Lim_AP_SH"
                upsamplers(iMethod).preprocessing = "SUpDEq_Lim_AP";
                upsamplers(iMethod).interpolation = "SH";
            case "SUpDEq_NN"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "NN";
            case "SUpDEq_MCA"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "SH";
                upsamplers(iMethod).magnitudeCorrectionDb = cfg.supdeq.publishedMcaDb;
            case "SUpDEq_NN_MCA_6dB"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "NN";
                upsamplers(iMethod).magnitudeCorrectionDb = cfg.supdeq.variantMcDb;
            case "SUpDEq_Bary_MCA_6dB"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "Bary";
                upsamplers(iMethod).magnitudeCorrectionDb = cfg.supdeq.variantMcDb;
            case "RANF"
                upsamplers(iMethod).preprocessing = "ExternalSOFA";
                upsamplers(iMethod).interpolation = "RANF";
            case "FSP_AE"
                upsamplers(iMethod).preprocessing = "ExternalSOFA";
                upsamplers(iMethod).interpolation = "FSP_AE";
            otherwise
                error("Unrecognised interpolation method: %s", methodName);
        end
    end

end

function cfg = apply_comparator_protocol_config(cfg, studyRoot)
% Opt-in LAP/Hu sparse-mask protocol used for the reported 41-subject
% comparison. This keeps the standard FPS evaluation available unless
% FISHERRAO_COMPARATOR_PROTOCOL_JSON is set.

    protocolPath = cfg.comparatorProtocol.path;
    assert(isfile(protocolPath), ...
        "Comparator protocol JSON does not exist: %s", protocolPath);
    protocol = jsondecode(fileread(protocolPath));

    cfg.resultsRoot = fullfile(studyRoot, "results", ...
        "barumerli_pge_fisher_hu_ml_comparators");
    cfg.subjectPopulation = double(protocol.subjectIds(:)).';
    cfg.subjectIds = double(protocol.testSubjectIds(:)).';
    cfg.validationIds = cfg.subjectIds;
    cfg.retentionConditions = double(protocol.retentions(:)).';
    cfg.samplingProvenance = ...
        "LAP/Hu hard-coded sparse masks, seeded 162/41 split";

    retained = struct();
    for iCondition = 1:numel(cfg.retentionConditions)
        count = cfg.retentionConditions(iCondition);
        key = string(count);
        zeroBased = double(read_json_object_field( ...
            protocol.sonicomDirectionIndices, key));
        retained.("N" + key) = zeroBased(:).' + 1;
    end
    cfg.comparatorProtocol.retainedIndices = retained;
    cfg.comparatorProtocol.trainSubjectIds = ...
        double(protocol.trainSubjectIds(:)).';
    cfg.comparatorProtocol.testSubjectIds = ...
        double(protocol.testSubjectIds(:)).';
    cfg.externalComparators.root = fullfile(studyRoot, ...
        "ml_comparator_research", "comparator_protocol", "work");
    cfg.externalComparators.alignedRoot = fullfile( ...
        cfg.externalComparators.root, "ml_lap_aligned");
    % Final reported comparator set. Earlier exploratory ML comparators are
    % omitted from the manuscript run because the reproduced public artefacts
    % did not provide paper-matching, independently verifiable results.
    cfg.methods = ["SUpDEq_SH", "SUpDEq_MCA", ...
        "SUpDEq_NN_MCA_6dB", "SUpDEq_Bary_MCA_6dB", ...
        "RANF", "FSP_AE"];

end

function value = read_json_object_field(object, key)
% jsondecode must convert JSON keys such as "100" into valid MATLAB field
% names. Try the likely transforms without requiring a MATLAB-version-
% specific assumption.

    candidates = unique([key, "x" + key, matlab.lang.makeValidName(key)], ...
        "stable");
    for iCandidate = 1:numel(candidates)
        field = candidates(iCandidate);
        if isfield(object, field)
            value = object.(field);
            return;
        end
    end
    error("JSON object does not contain key %s.", key);

end

function sampling = create_sampling_conditions(dataset, cfg)
% Apply one deterministic nested farthest-point ordering to the common
% measured grid so that each denser condition contains every sparser point.

    referenceR = dataset(1).r;

    for iSubject = 2:numel(dataset)
        assert(isequal(size(referenceR), size(dataset(iSubject).r)) && ...
            max(abs(referenceR - dataset(iSubject).r), [], "all") < ...
            cfg.uniqueDirectionTolerance, ...
            "All subjects must share the same direction grid for common FPS masks.");
    end

    counts = cfg.retentionConditions;
    assert(all(counts == fix(counts)) && all(counts >= 1) && ...
        all(counts <= size(referenceR, 1)), ...
        "cfg.retentionConditions must contain valid retained direction counts.");

    sampling = repmat(struct("retentionCount", [], "retainedIndices", [], ...
        "fpsOrdering", [], "randomSeed", cfg.randomSeed), 1, numel(counts));

    if isfield(cfg, "comparatorProtocol") && cfg.comparatorProtocol.enabled
        for iCondition = 1:numel(counts)
            key = "N" + string(counts(iCondition));
            assert(isfield(cfg.comparatorProtocol.retainedIndices, key), ...
                "Comparator protocol does not contain retained indices for %s.", key);
            retained = cfg.comparatorProtocol.retainedIndices.(key);
            assert(all(retained >= 1) && all(retained <= size(referenceR, 1)), ...
                "Comparator protocol retained indices for %s are outside the loaded direction grid.", key);
            sampling(iCondition).retentionCount = counts(iCondition);
            sampling(iCondition).retainedIndices = sort(retained(:).');
            sampling(iCondition).fpsOrdering = retained(:).';
        end
    else
        ordering = farthest_point_order(referenceR, max(counts), cfg);
        for iCondition = 1:numel(counts)
            sampling(iCondition).retentionCount = counts(iCondition);
            sampling(iCondition).retainedIndices = ...
                sort(ordering(1:counts(iCondition)));
            sampling(iCondition).fpsOrdering = ordering;
        end
    end

end

function ordering = farthest_point_order(r, numberToRetain, cfg)
% Greedy FPS using squared chordal distance on the unit sphere. Only the
% first point is random; its selection is reproduced exactly by randomSeed.

    nDirections = size(r, 1);
    ordering = zeros(1, numberToRetain);
    available = true(nDirections, 1);

    if isempty(cfg.fpsInitialIndex)
        stream = RandStream("mt19937ar", "Seed", cfg.randomSeed);
        ordering(1) = randi(stream, nDirections);
    else
        assert(cfg.fpsInitialIndex >= 1 && cfg.fpsInitialIndex <= nDirections, ...
            "cfg.fpsInitialIndex lies outside the direction grid.");
        ordering(1) = cfg.fpsInitialIndex;
    end

    available(ordering(1)) = false;
    minDistanceSquared = sum((r - r(ordering(1), :)) .^ 2, 2);

    for iPoint = 2:numberToRetain

        minDistanceSquared(~available) = -Inf;
        [~, nextIndex] = max(minDistanceSquared);
        ordering(iPoint) = nextIndex;
        available(nextIndex) = false;

        newDistanceSquared = sum((r - r(nextIndex, :)) .^ 2, 2);
        minDistanceSquared = min(minDistanceSquared, newDistanceSquared);

    end

end

function sparseField = subset_spatial_field(field, retainedIndices)

    sparseField = field;
    sparseField.r = field.r(retainedIndices, :);
    sparseField.azElDeg = field.azElDeg(retainedIndices, :);
    sparseField.hrir = field.hrir(retainedIndices, :, :);
    sparseField.complexHrtf = field.complexHrtf(retainedIndices, :, :);
    sparseField.hrtfMag = field.hrtfMag(retainedIndices, :, :);
    sparseField.retainedIndices = retainedIndices;

end

function recon = reconstruct_hrtf_field(sparseField, targetR, method, cfg)
% Call the official SUpDEq interpolation entry point, then return data in
% the internal direction-major convention.

    if method.preprocessing == "ExternalSOFA"
        recon = load_external_comparator_reconstruction( ...
            sparseField, targetR, method, cfg);
        return;
    end

    if method.interpolation == "Bary" && size(sparseField.r, 1) < 4
        recon = unavailable_reconstruction(sparseField, targetR, method.name, ...
            "Not applicable: three directions cannot define the closed hull required by SUpDEq Bary.");
        recon.barycentricFallbackCount = NaN;
        return;
    end

    assert(exist("supdeq_interpHRTF", "file") == 2, ...
        "supdeq_interpHRTF was not found. Set cfg.toolbox.supdeqRoot.");

    HRTFset = form_supdeq_input(sparseField, cfg);
    targetAzElDeg = cartesian_to_az_el(targetR);
    appliedInterpolation = method.interpolation;
    interpolationGrid = to_supdeq_sampling_grid( ...
        cartesian_to_az_el(targetR));

    if ~isnan(method.magnitudeCorrectionDb)
        clear AKerbErrorPersistent;
    end

    try
        [interpolatedSet, HRTFLeft, HRTFRight] = supdeq_interpHRTF( ...
            HRTFset, interpolationGrid, char(method.preprocessing), ...
            char(appliedInterpolation), method.magnitudeCorrectionDb, ...
            cfg.headRadius, cfg.supdeq.tikhEps, cfg.supdeq.limitMC, ...
            cfg.supdeq.mcKnee, cfg.supdeq.mcMinPhase, ...
            char(cfg.supdeq.limFade));
    catch exception
        if ~isnan(method.magnitudeCorrectionDb)
            clear AKerbErrorPersistent;
            [interpolatedSet, HRTFLeft, HRTFRight] = supdeq_interpHRTF( ...
                HRTFset, interpolationGrid, char(method.preprocessing), ...
                char(appliedInterpolation), method.magnitudeCorrectionDb, ...
                cfg.headRadius, cfg.supdeq.tikhEps, cfg.supdeq.limitMC, ...
                cfg.supdeq.mcKnee, cfg.supdeq.mcMinPhase, ...
                char(cfg.supdeq.limFade));
        else
            rethrow(exception);
        end
    end

    supdeqComplexHrtf = normalise_supdeq_output(HRTFLeft, HRTFRight, ...
        size(targetR, 1), cfg.nFreqBins + 1);

    recon = sparseField;
    recon.r = targetR;
    recon.azElDeg = targetAzElDeg;
    recon.hrir = permute(cat(3, interpolatedSet.HRIR_L, ...
        interpolatedSet.HRIR_R), [2, 3, 1]);
    recon = refresh_field_spectra(recon, cfg);
    % Real HRIRs cannot retain imaginary DC/Nyquist components sometimes
    % returned by SUpDEq. Require every physically meaningful interior bin
    % to remain exact, and evaluate the playable real-valued reconstruction.
    spectralDifference = recon.complexHrtf(:, 2:end-1, :) - ...
        supdeqComplexHrtf(:, 2:end-1, :);
    interiorRelativeError = norm(spectralDifference(:)) / ...
        max(norm(reshape(supdeqComplexHrtf(:, 2:end-1, :), [], 1)), eps);
    recon.supdeqInteriorRelativeError = interiorRelativeError;
    recon.hasInterauralDelay = true;
    recon.itdProvenance = "complex_hrtf_reconstruction";
    recon.methodName = method.name;
    recon.isAvailable = true;
    recon.message = "";
    if method.interpolation == "Bary"
        if isfield(interpolatedSet, "barycentricFallbackCount")
            recon.barycentricFallbackCount = ...
                double(interpolatedSet.barycentricFallbackCount);
        else
            recon.barycentricFallbackCount = 0;
        end
    end

end

function recon = load_external_comparator_reconstruction( ...
    sparseField, targetR, method, cfg)
% Load a generated comparator SOFA and map it onto the measured target grid.

    retentionCount = numel(sparseField.retainedIndices);
    [filePath, message] = resolve_external_comparator_sofa( ...
        sparseField.subjectId, retentionCount, method.name, cfg);

    if strlength(filePath) == 0
        recon = unavailable_reconstruction(sparseField, targetR, ...
            method.name, message);
        recon.barycentricFallbackCount = NaN;
        return;
    end

    external = read_sofa_hrtf_field(filePath, cfg);
    recon = resample_external_field_to_target_grid(external, targetR, cfg);
    recon.subjectId = sparseField.subjectId;
    recon.filePath = filePath;
    recon.methodName = method.name;
    recon.isAvailable = true;
    recon.message = "";
    recon.hasInterauralDelay = true;
    recon.itdProvenance = "external_comparator_sofa";
    recon.barycentricFallbackCount = NaN;

end

function [filePath, message] = resolve_external_comparator_sofa( ...
    subjectId, retentionCount, methodName, cfg)

    filePath = "";
    message = "";

    if ~isfield(cfg, "externalComparators") || ...
            ~isfield(cfg.externalComparators, "root")
        message = "External comparator root is not configured.";
        return;
    end

    root = cfg.externalComparators.root;
    if isfield(cfg.externalComparators, "alignedRoot") && ...
            strlength(string(cfg.externalComparators.alignedRoot)) > 0
        alignedRoot = string(cfg.externalComparators.alignedRoot);
        alignedPath = fullfile(alignedRoot, string(methodName), ...
            sprintf("N%03d", retentionCount), ...
            sprintf("Sonicom_%d.sofa", subjectId));
        if isfile(alignedPath)
            filePath = alignedPath;
            return;
        end
        if isfolder(alignedRoot) && ismember(string(methodName), ...
                ["RANF", "FSP_AE"])
            message = sprintf([ ...
                "LAP-aligned external comparator SOFA not found: %s. " ...
                "Inspect ml_lap_alignment_report.csv and the exported " ...
                "ml_lap_aligned comparator folders."], alignedPath);
            return;
        end
    end

    switch string(methodName)
        case "RANF"
            pattern = fullfile(root, "ranf_sonicom", "experiments", ...
                sprintf("ranf_hu_N%03d", retentionCount), "log", "eval", ...
                sprintf("pred_p%04d.sofa", subjectId));
        case "FSP_AE"
            pattern = fullfile(root, "ml_lap_aligned", "FSP_AE", ...
                sprintf("N%03d", retentionCount), ...
                sprintf("Sonicom_%d.sofa", subjectId));
        otherwise
            message = "Unrecognised external comparator method.";
            return;
    end

    matches = dir(pattern);
    if isempty(matches)
        message = sprintf("External comparator SOFA not found: %s", pattern);
        return;
    end

    [~, newest] = max([matches.datenum]);
    filePath = string(fullfile(matches(newest).folder, matches(newest).name));

end

function recon = resample_external_field_to_target_grid(external, targetR, cfg)
% Map an external comparator SOFA onto the measured SONICOM target grid.
% Current exported comparator SOFAs should match the SONICOM grid up to
% numerical roundoff.
 
    nearest = nearest_direction_indices(external.r, targetR);
    angularErrorDeg = rad2deg(acos(max(min( ...
        sum(external.r(nearest, :) .* targetR, 2), 1), -1)));
    maxErrorDeg = max(angularErrorDeg);
 
    gridToleranceDeg = 1e-4;
    assert(maxErrorDeg <= gridToleranceDeg, ...
        "External SOFA directions do not match the target SONICOM grid. Max angular mismatch: %.6f deg.", ...
        maxErrorDeg);
 
    recon = external;
    recon.r = targetR;
    recon.azElDeg = cartesian_to_az_el(targetR);
    recon.hrir = external.hrir(nearest, :, :);
    recon = refresh_field_spectra(recon, cfg);
 
end

function nearest = nearest_direction_indices(sourceR, targetR)

    nearest = zeros(size(targetR, 1), 1);
    for iDirection = 1:size(targetR, 1)
        distances = sum((sourceR - targetR(iDirection, :)) .^ 2, 2);
        [~, nearest(iDirection)] = min(distances);
    end

end

function recon = unavailable_reconstruction(sparseField, targetR, methodName, message)

    recon = sparseField;
    recon.r = targetR;
    recon.azElDeg = cartesian_to_az_el(targetR);
    recon.methodName = methodName;
    recon.isAvailable = false;
    recon.message = message;

end

function HRTFset = form_supdeq_input(field, cfg)
% SUpDEq uses [direction x frequency] spectra and polar elevation:
% elevation 0 deg is the north pole and 90 deg is the horizontal plane.

    nDirections = size(field.r, 1);
    maximumResolvableOrder = max(0, floor(sqrt(nDirections) - 1));

    if isfield(field, "fftLength") && ~isempty(field.fftLength)
        fftLength = field.fftLength;
    elseif ~isempty(cfg.fftLength)
        fftLength = cfg.fftLength;
    else
        fftLength = size(field.hrir, 3);
    end

    assert(isscalar(fftLength) && isfinite(fftLength), ...
        "SUpDEq requires a scalar FFT length.");

    fftOversize = fftLength / size(field.hrir, 3);
    assert(isscalar(fftOversize) && abs(fftOversize - round(fftOversize)) < eps, ...
        "cfg.fftLength must be an integer multiple of the processed HRIR length for SUpDEq.");

    HRTFset.HRTF_L = squeeze(field.complexHrtf(:, :, 1));
    HRTFset.HRTF_R = squeeze(field.complexHrtf(:, :, 2));
    HRTFset.f = field.freqHzWithDC;
    HRTFset.fs = field.fs;
    HRTFset.FFToversize = round(fftOversize);
    HRTFset.Nmax = min(cfg.supdeq.maxSHOrder, maximumResolvableOrder);
    HRTFset.samplingGrid = to_supdeq_sampling_grid(field.azElDeg);

end

function grid = to_supdeq_sampling_grid(azElDeg)

    azimuthDeg = mod(azElDeg(:, 1), 360);
    polarElevationDeg = 90 - azElDeg(:, 2);
    grid = [azimuthDeg, polarElevationDeg];

end

function azElDeg = cartesian_to_az_el(r)

    r = r ./ vecnorm(r, 2, 2);
    [azimuth, elevation, ~] = cart2sph(r(:, 1), r(:, 2), r(:, 3));
    azElDeg = rad2deg([azimuth, elevation]);

end

function complexHrtf = normalise_supdeq_output(left, right, ...
        nDirections, nFrequencyBins)

    left = orient_direction_major_spectra(left, nDirections);
    right = orient_direction_major_spectra(right, nDirections);

    assert(size(left, 2) >= nFrequencyBins && ...
        size(right, 2) >= nFrequencyBins, ...
        "SUpDEq returned fewer one-sided frequency bins than requested.");

    complexHrtf = cat(3, left(:, 1:nFrequencyBins), ...
        right(:, 1:nFrequencyBins));

end

function spectra = orient_direction_major_spectra(spectra, nDirections)

    if size(spectra, 1) == nDirections
        return;
    elseif size(spectra, 2) == nDirections
        spectra = spectra.';
    else
        error("SUpDEq output dimensions do not match the requested grid.");
    end

end

function lsd = compute_binaural_lsd(targetHrir, reconHrir, fs, cfg)
% SAM/LAP-compatible HRIR-domain LSD.
% spatialaudiometrics computes the FFT from HRIRs, keeps positive
% frequencies below Nyquist, restricts to 20--20000 Hz, computes an RMS
% log-magnitude ratio for each direction/ear, then averages. When two
% reconstruction routes return different HRIR lengths, compare them at a
% shared zero-padded FFT length rather than requiring identical sample
% counts.

    assert(isequal([size(targetHrir, 1), size(targetHrir, 2)], ...
        [size(reconHrir, 1), size(reconHrir, 2)]), ...
        "LAP/SAM LSD requires target and reconstructed HRIRs on the same direction/ear grid.");
    nSamples = max(size(targetHrir, 3), size(reconHrir, 3));
    nPositive = floor(nSamples / 2);
    freqs = (0:(nPositive - 1)) * fs / nSamples;
    freqIdx = freqs >= 20 & freqs <= 20000;
    assert(any(freqIdx), "No FFT bins fall inside the LAP/SAM LSD band.");

    targetSpec = fft(targetHrir, nSamples, 3);
    reconSpec = fft(reconHrir, nSamples, 3);
    targetMag = abs(targetSpec(:, :, 1:nPositive));
    reconMag = abs(reconSpec(:, :, 1:nPositive));

    targetBand = targetMag(:, :, freqIdx);
    reconBand = reconMag(:, :, freqIdx);
    lsdByDirectionEar = sqrt(mean((20 * log10( ...
        max(targetBand, cfg.epsMag) ./ max(reconBand, cfg.epsMag))) .^ 2, 3));
    lsd = mean(lsdByDirectionEar, "all");

end

function ildError = compute_ild_error(targetHrir, reconHrir, cfg)
% SAM/LAP-compatible ILD difference from HRIR RMS energy.

    targetRms = sqrt(mean(targetHrir .^ 2, 3));
    reconRms = sqrt(mean(reconHrir .^ 2, 3));

    targetILD = 20 * log10(max(targetRms(:, 1), cfg.epsMag) ./ ...
        max(targetRms(:, 2), cfg.epsMag));
    reconILD = 20 * log10(max(reconRms(:, 1), cfg.epsMag) ./ ...
        max(reconRms(:, 2), cfg.epsMag));

    ildError = mean(abs(targetILD - reconILD), "all");

end

function selected = is_selected_perceptual_condition(method, retentionCount, cfg)

    selected = ismember(method.name, cfg.perceptual.methods) && ...
        ismember(retentionCount, cfg.perceptual.retentionConditions);

end

function template = create_barumerli_template(target, cfg)
% Generate the model's internal template from the measured reference DTFs.

    referenceDtf = convert_field_to_dtf_sofa(target, target, cfg);
    template = barumerli2023_featureextraction(referenceDtf, ...
        'template', char(cfg.perceptual.featureSpace));

end

function [result, isAvailable] = saved_self_reference_result(summary, subjectId, cfg)
% Recover a self-reference already propagated into a resumed summary table.

    result = not_run_perceptual_result("not_run", ...
        "Dense self-reference has not yet been evaluated.");
    isAvailable = false;
    if isempty(summary) || ~ismember("selfLateralRMSErrorDeg", ...
            string(summary.Properties.VariableNames))
        return;
    end

    idx = summary.subjectId == subjectId & ...
        ~isnan(summary.selfLateralRMSErrorDeg) & ...
        ~isnan(summary.selfLocalPolarRMSErrorDeg) & ...
        ~isnan(summary.selfQuadrantErrorPercent);
    if ismember("selfPerceptualTrials", string(summary.Properties.VariableNames))
        idx = idx & summary.selfPerceptualTrials == cfg.perceptual.numExperiments;
    end
    first = find(idx, 1, "first");
    if isempty(first)
        return;
    end

    result.status = "completed";
    result.message = "";
    result.lateralRMSErrorDeg = summary.selfLateralRMSErrorDeg(first);
    result.localPolarRMSErrorDeg = summary.selfLocalPolarRMSErrorDeg(first);
    result.quadrantErrorPercent = summary.selfQuadrantErrorPercent(first);
    result.numExperiments = cfg.perceptual.numExperiments;
    isAvailable = true;

end

function result = evaluate_barumerli_model(referenceTemplate, target, recon, cfg, targetFeatures)
% Evaluate one reconstruction as a Barumerli target stimulus while the
% measured HRTF supplies the fixed internal template.

    if nargin < 5 || isempty(fieldnames(targetFeatures))
        reconstructedDtf = convert_field_to_dtf_sofa(recon, target, cfg);
        targetFeatures = barumerli2023_featureextraction(reconstructedDtf, ...
            'target', char(cfg.perceptual.featureSpace));
    end
    assert_barumerli_target_coordinates(targetFeatures, target.r, ...
        cfg.uniqueDirectionTolerance);

    rng(cfg.perceptual.randomSeed, "twister");
    responses = [];
    experimentsRemaining = cfg.perceptual.numExperiments;
    % barumerli2023 constructs a full posterior for each repetition.
    % Accumulate identical-model batches to keep the full study tractable
    % without changing the requested number of simulated experiments.
    while experimentsRemaining > 0
        experimentsInBatch = min(cfg.perceptual.experimentsPerBatch, ...
            experimentsRemaining);
        batchResponses = barumerli2023( ...
            'template', referenceTemplate, ...
            'target', targetFeatures, ...
            'num_exp', experimentsInBatch, ...
            'sigma_itd', cfg.perceptual.sigmaITD, ...
            'sigma_ild', cfg.perceptual.sigmaILD, ...
            'sigma_spectral', cfg.perceptual.sigmaSpectral, ...
            'sigma_prior', cfg.perceptual.sigmaPrior, ...
            'sigma_motor', cfg.perceptual.sigmaMotor, ...
            char(cfg.perceptual.estimator));
        responses = [responses; batchResponses]; %#ok<AGROW>
        experimentsRemaining = experimentsRemaining - experimentsInBatch;
    end

    modelMetrics = barumerli2023_metrics(responses, 'middle_metrics');

    result = not_run_perceptual_result("completed", "");
    result.lateralBiasDeg = modelMetrics.accL;
    result.lateralRMSErrorDeg = modelMetrics.rmsL;
    result.polarBiasDeg = modelMetrics.accP;
    result.localPolarRMSErrorDeg = modelMetrics.rmsP;
    result.quadrantErrorPercent = modelMetrics.querr;
    result.polarGain = modelMetrics.gainP;
    result.numExperiments = cfg.perceptual.numExperiments;

end

function result = attach_self_reference_metrics(result, selfReference, cfg)
% Store absolute metrics and their signed degradation relative to dense self.

    if ~cfg.perceptual.reportRelativeToSelf || selfReference.status ~= "completed"
        return;
    end

    result.selfLateralRMSErrorDeg = selfReference.lateralRMSErrorDeg;
    result.selfLocalPolarRMSErrorDeg = selfReference.localPolarRMSErrorDeg;
    result.selfQuadrantErrorPercent = selfReference.quadrantErrorPercent;
    result.selfPerceptualTrials = selfReference.numExperiments;
    result.referenceConvention = "absolute_and_relative_to_dense_self";

    if result.status == "completed"
        result.relativeLateralRMSErrorDeg = result.lateralRMSErrorDeg - ...
            selfReference.lateralRMSErrorDeg;
        result.relativeLocalPolarRMSErrorDeg = result.localPolarRMSErrorDeg - ...
            selfReference.localPolarRMSErrorDeg;
        result.relativeQuadrantErrorPercentagePoints = ...
            result.quadrantErrorPercent - selfReference.quadrantErrorPercent;
    end

end

function dtf = convert_field_to_dtf_sofa(field, layoutField, cfg)
% Place a measured or reconstructed HRIR field into the measured SOFA
% layout, then apply the same SOFA DTF convention used for all conditions.

    sofa = layoutField.sofaObject;
    assert(size(field.hrir, 1) == size(sofa.SourcePosition, 1), ...
        "Perceptual evaluation requires reconstruction on the reference grid.");
    assert(size(field.hrir, 2) == size(sofa.Data.IR, 2), ...
        "Perceptual evaluation requires the reference binaural layout.");
    if isfield(sofa.Data, "Delay")
        assert(all(abs(sofa.Data.Delay(:)) < eps), ...
            "SOFA Data.Delay must be zero or incorporated into HRIRs before DTF conversion.");
        sofa.Data.Delay(:) = 0;
    end
    sofa.Data.IR = real(field.hrir);
    sofa.Data.SamplingRate = field.fs;
    sofa = SOFAupdateDimensions(sofa);

    switch cfg.perceptual.dtfConvention
        case "log"
            dtf = SOFAhrtf2dtf(sofa, 'log');
        case "rms"
            dtf = SOFAhrtf2dtf(sofa, 'rms');
        otherwise
            error("Unsupported Barumerli DTF convention: %s", ...
                cfg.perceptual.dtfConvention);
    end

end

function result = not_run_perceptual_result(status, message)

    result.status = string(status);
    result.message = string(message);
    result.lateralBiasDeg = NaN;
    result.lateralRMSErrorDeg = NaN;
    result.polarBiasDeg = NaN;
    result.localPolarRMSErrorDeg = NaN;
    result.quadrantErrorPercent = NaN;
    result.polarGain = NaN;
    result.numExperiments = NaN;
    result.selfLateralRMSErrorDeg = NaN;
    result.selfLocalPolarRMSErrorDeg = NaN;
    result.selfQuadrantErrorPercent = NaN;
    result.selfPerceptualTrials = NaN;
    result.relativeLateralRMSErrorDeg = NaN;
    result.relativeLocalPolarRMSErrorDeg = NaN;
    result.relativeQuadrantErrorPercentagePoints = NaN;
    result.referenceConvention = "absolute_only";

end

function summary = add_perceptual_reference_columns(summary)
% Upgrade checkpoints written before dense self-reference reporting existed.

    if isempty(summary)
        return;
    end

    numericColumns = ["selfLateralRMSErrorDeg", ...
        "selfLocalPolarRMSErrorDeg", "selfQuadrantErrorPercent", ...
        "selfPerceptualTrials", "relativeLateralRMSErrorDeg", ...
        "relativeLocalPolarRMSErrorDeg", ...
        "relativeQuadrantErrorPercentagePoints"];
    existing = string(summary.Properties.VariableNames);
    for iColumn = 1:numel(numericColumns)
        if ~ismember(numericColumns(iColumn), existing)
            summary.(numericColumns(iColumn)) = nan(height(summary), 1);
        end
    end
    if ~ismember("perceptualReferenceConvention", existing)
        summary.perceptualReferenceConvention = ...
            repmat("absolute_only", height(summary), 1);
    end

end

function summary = replace_perceptual_summary_row(summary, row, perceptual)
% Replace only observer-model outputs, preserving all completed objective
% and Fisher-tensor quantities in the existing evaluation row.

    summary.perceptualStatus(row) = perceptual.status;
    summary.lateralRMSErrorDeg(row) = perceptual.lateralRMSErrorDeg;
    summary.localPolarRMSErrorDeg(row) = perceptual.localPolarRMSErrorDeg;
    summary.quadrantErrorPercent(row) = perceptual.quadrantErrorPercent;
    summary.perceptualTrials(row) = perceptual.numExperiments;
    summary.selfLateralRMSErrorDeg(row) = ...
        perceptual.selfLateralRMSErrorDeg;
    summary.selfLocalPolarRMSErrorDeg(row) = ...
        perceptual.selfLocalPolarRMSErrorDeg;
    summary.selfQuadrantErrorPercent(row) = ...
        perceptual.selfQuadrantErrorPercent;
    summary.selfPerceptualTrials(row) = perceptual.selfPerceptualTrials;
    summary.relativeLateralRMSErrorDeg(row) = ...
        perceptual.relativeLateralRMSErrorDeg;
    summary.relativeLocalPolarRMSErrorDeg(row) = ...
        perceptual.relativeLocalPolarRMSErrorDeg;
    summary.relativeQuadrantErrorPercentagePoints(row) = ...
        perceptual.relativeQuadrantErrorPercentagePoints;
    summary.perceptualReferenceConvention(row) = ...
        perceptual.referenceConvention;

end

function summary = apply_self_reference_to_existing_rows( ...
        summary, subjectId, selfReference, cfg)
% Add a newly computed self-reference to any completed rows from a resume.

    if isempty(summary) || ~cfg.perceptual.reportRelativeToSelf || ...
            selfReference.status ~= "completed"
        return;
    end

    idx = summary.subjectId == subjectId & ...
        ismember(summary.method, cfg.perceptual.methods) & ...
        ismember(summary.retainedDirections, ...
            cfg.perceptual.retentionConditions);
    summary.selfLateralRMSErrorDeg(idx) = selfReference.lateralRMSErrorDeg;
    summary.selfLocalPolarRMSErrorDeg(idx) = selfReference.localPolarRMSErrorDeg;
    summary.selfQuadrantErrorPercent(idx) = selfReference.quadrantErrorPercent;
    summary.selfPerceptualTrials(idx) = selfReference.numExperiments;
    summary.perceptualReferenceConvention(idx) = ...
        "absolute_and_relative_to_dense_self";

    completed = idx & summary.perceptualStatus == "completed";
    summary.relativeLateralRMSErrorDeg(completed) = ...
        summary.lateralRMSErrorDeg(completed) - selfReference.lateralRMSErrorDeg;
    summary.relativeLocalPolarRMSErrorDeg(completed) = ...
        summary.localPolarRMSErrorDeg(completed) - ...
        selfReference.localPolarRMSErrorDeg;
    summary.relativeQuadrantErrorPercentagePoints(completed) = ...
        summary.quadrantErrorPercent(completed) - ...
        selfReference.quadrantErrorPercent;

end

function result = unavailable_fisher_result(nDirections, message, cfg)

    result.meanAIRM = NaN;
    result.medianAIRM = NaN;
    result.stdAIRM = NaN;
    result.iqrAIRM = NaN;
    result.airmByDirection = nan(nDirections, 1);
    result.meanDeterminantError = NaN;
    result.determinantErrorByDirection = nan(nDirections, 1);
    result.meanAnisotropyError = NaN;
    result.anisotropyErrorByDirection = nan(nDirections, 1);
    result.orientationErrorByDirection = nan(nDirections, 1);
    result.meanOrientationErrorRad = NaN;
    result.meanOrientationErrorDeg = NaN;
    result.orientationValidCount = NaN;
    result.orientationValidProportion = NaN;
    result.targetITDMode = "not_applicable";
    result.reconstructedITDMode = "not_applicable";
    result.cueExtractionMode = cfg.fisher.cueConvention;
    result.targetTensor = nan(2, 2, nDirections);
    result.reconstructedTensor = nan(2, 2, nDirections);
    result.targetPrincipalMAA = nan(nDirections, 2);
    result.reconstructedPrincipalMAA = nan(nDirections, 2);
    result.status = "not_applicable";
    result.message = message;

end

function summary = build_airm_summary_table(dataset, evaluationIndices, ...
        upsamplers, sampling, reconstructions, signalResults, fisherResults, ...
        perceptualResults)

    nRows = numel(evaluationIndices) * numel(sampling) * numel(upsamplers);
    subjectId = zeros(nRows, 1);
    method = strings(nRows, 1);
    retainedDirections = zeros(nRows, 1);
    barycentricFallbackCount = nan(nRows, 1);
    status = strings(nRows, 1);
    message = strings(nRows, 1);
    meanAIRM = zeros(nRows, 1);
    medianAIRM = zeros(nRows, 1);
    stdAIRM = zeros(nRows, 1);
    iqrAIRM = zeros(nRows, 1);
    meanDeterminantError = zeros(nRows, 1);
    meanAnisotropyError = zeros(nRows, 1);
    meanOrientationErrorDeg = zeros(nRows, 1);
    orientationValidCount = zeros(nRows, 1);
    orientationValidProportion = zeros(nRows, 1);
    targetITDMode = strings(nRows, 1);
    reconstructedITDMode = strings(nRows, 1);
    cueExtractionMode = strings(nRows, 1);
    LSDdB = zeros(nRows, 1);
    ILDErrorDb = zeros(nRows, 1);
    perceptualStatus = strings(nRows, 1);
    lateralRMSErrorDeg = nan(nRows, 1);
    localPolarRMSErrorDeg = nan(nRows, 1);
    quadrantErrorPercent = nan(nRows, 1);
    perceptualTrials = nan(nRows, 1);
    selfLateralRMSErrorDeg = nan(nRows, 1);
    selfLocalPolarRMSErrorDeg = nan(nRows, 1);
    selfQuadrantErrorPercent = nan(nRows, 1);
    selfPerceptualTrials = nan(nRows, 1);
    relativeLateralRMSErrorDeg = nan(nRows, 1);
    relativeLocalPolarRMSErrorDeg = nan(nRows, 1);
    relativeQuadrantErrorPercentagePoints = nan(nRows, 1);
    perceptualReferenceConvention = strings(nRows, 1);

    row = 0;

    for iSub = 1:numel(evaluationIndices)
        for iCond = 1:numel(sampling)
            for iMethod = 1:numel(upsamplers)

                row = row + 1;
                fisher = fisherResults(iSub, iCond, iMethod);
                signal = signalResults(iSub, iCond, iMethod);
                recon = reconstructions{iSub, iCond, iMethod};
                perceptual = perceptualResults(iSub, iCond, iMethod);

                subjectId(row) = dataset(evaluationIndices(iSub)).subjectId;
                method(row) = upsamplers(iMethod).name;
                retainedDirections(row) = sampling(iCond).retentionCount;
                if isfield(recon, "barycentricFallbackCount")
                    barycentricFallbackCount(row) = recon.barycentricFallbackCount;
                end
                status(row) = fisher.status;
                message(row) = recon.message;
                if strlength(fisher.message) > 0
                    message(row) = fisher.message;
                end
                meanAIRM(row) = fisher.meanAIRM;
                medianAIRM(row) = fisher.medianAIRM;
                stdAIRM(row) = fisher.stdAIRM;
                iqrAIRM(row) = fisher.iqrAIRM;
                meanDeterminantError(row) = fisher.meanDeterminantError;
                meanAnisotropyError(row) = fisher.meanAnisotropyError;
                meanOrientationErrorDeg(row) = fisher.meanOrientationErrorDeg;
                orientationValidCount(row) = fisher.orientationValidCount;
                orientationValidProportion(row) = fisher.orientationValidProportion;
                targetITDMode(row) = fisher.targetITDMode;
                reconstructedITDMode(row) = fisher.reconstructedITDMode;
                cueExtractionMode(row) = fisher.cueExtractionMode;
                LSDdB(row) = signal.LSD;
                ILDErrorDb(row) = signal.ILD;
                perceptualStatus(row) = perceptual.status;
                lateralRMSErrorDeg(row) = perceptual.lateralRMSErrorDeg;
                localPolarRMSErrorDeg(row) = perceptual.localPolarRMSErrorDeg;
                quadrantErrorPercent(row) = perceptual.quadrantErrorPercent;
                perceptualTrials(row) = perceptual.numExperiments;
                selfLateralRMSErrorDeg(row) = perceptual.selfLateralRMSErrorDeg;
                selfLocalPolarRMSErrorDeg(row) = ...
                    perceptual.selfLocalPolarRMSErrorDeg;
                selfQuadrantErrorPercent(row) = perceptual.selfQuadrantErrorPercent;
                selfPerceptualTrials(row) = perceptual.selfPerceptualTrials;
                relativeLateralRMSErrorDeg(row) = ...
                    perceptual.relativeLateralRMSErrorDeg;
                relativeLocalPolarRMSErrorDeg(row) = ...
                    perceptual.relativeLocalPolarRMSErrorDeg;
                relativeQuadrantErrorPercentagePoints(row) = ...
                    perceptual.relativeQuadrantErrorPercentagePoints;
                perceptualReferenceConvention(row) = perceptual.referenceConvention;

            end
        end
    end

    summary = table(subjectId, method, retainedDirections, ...
        barycentricFallbackCount, status, message, meanAIRM, medianAIRM, ...
        stdAIRM, iqrAIRM, meanDeterminantError, meanAnisotropyError, ...
        meanOrientationErrorDeg, orientationValidCount, ...
        orientationValidProportion, targetITDMode, reconstructedITDMode, ...
        cueExtractionMode, LSDdB, ILDErrorDb, perceptualStatus, lateralRMSErrorDeg, ...
        localPolarRMSErrorDeg, quadrantErrorPercent, perceptualTrials, ...
        selfLateralRMSErrorDeg, selfLocalPolarRMSErrorDeg, ...
        selfQuadrantErrorPercent, selfPerceptualTrials, ...
        relativeLateralRMSErrorDeg, relativeLocalPolarRMSErrorDeg, ...
        relativeQuadrantErrorPercentagePoints, perceptualReferenceConvention);

end

function ensure_results_folder(resultsRoot)

    if ~isfolder(resultsRoot)
        mkdir(resultsRoot);
    end

end

function plot_metric_relationships(summary, cfg)
% Plot signal-level errors against Fisher-tensor discrepancy.

    valid = summary.status == "completed";
    conditions = unique(summary.retainedDirections(valid), "stable");
    colors = lines(numel(conditions));
    fig = figure("Visible", char(cfg.plots.visible), "Color", "w", ...
        "Name", "Metric relationships");
    tiledlayout(fig, 1, 2, "Padding", "compact", "TileSpacing", "compact");

    nexttile;
    hold on;
    for iCondition = 1:numel(conditions)
        idx = valid & summary.retainedDirections == conditions(iCondition);
        scatter(summary.LSDdB(idx), summary.meanAIRM(idx), 38, ...
            colors(iCondition, :), "filled", ...
            "DisplayName", sprintf("%d directions", conditions(iCondition)));
    end
    xlabel("LSD (dB)");
    ylabel("Mean AIRM distance");
    title("Spectral Error vs Fisher Geometry");
    grid on;
    legend("Location", "best");

    nexttile;
    hold on;
    for iCondition = 1:numel(conditions)
        idx = valid & summary.retainedDirections == conditions(iCondition);
        scatter(summary.ILDErrorDb(idx), summary.meanAIRM(idx), 38, ...
            colors(iCondition, :), "filled", ...
            "DisplayName", sprintf("%d directions", conditions(iCondition)));
    end
    xlabel("ILD error (dB)");
    ylabel("Mean AIRM distance");
    title("Binaural Level Error vs Fisher Geometry");
    grid on;
    legend("Location", "best");

    exportgraphics(fig, fullfile(cfg.resultsRoot, "metric_relationships.png"), ...
        "Resolution", 220);
    close(fig);

end

function plot_spatial_fisher_maps(dataset, evaluationIndices, upsamplers, ...
        sampling, fisherResults, cfg)
% Plot direction-wise tensor errors for a representative reconstruction.

    [iCondition, iMethod] = selected_plot_condition(upsamplers, sampling, cfg);
    result = fisherResults(1, iCondition, iMethod);
    assert(result.status == "completed", ...
        "Representative plotting condition is not available.");

    target = dataset(evaluationIndices(1));
    azEl = plotting_azimuth_elevation(target.azElDeg);
    values = {result.airmByDirection, result.determinantErrorByDirection, ...
        result.anisotropyErrorByDirection, ...
        rad2deg(result.orientationErrorByDirection)};
    titles = {"AIRM distance", "Determinant error", ...
        "Anisotropy error", "Orientation error (deg)"};

    fig = figure("Visible", char(cfg.plots.visible), "Color", "w", ...
        "Name", "Spatial Fisher maps");
    tiledlayout(fig, 2, 2, "Padding", "compact", "TileSpacing", "compact");

    for iPanel = 1:numel(values)
        nexttile;
        scatter(azEl(:, 1), azEl(:, 2), 24, values{iPanel}, "filled");
        xlabel("Azimuth (deg)");
        ylabel("Elevation (deg)");
        title(titles{iPanel});
        xlim([-180, 180]);
        ylim([-90, 90]);
        grid on;
        colorbar;
    end
    colormap(fig, turbo);
    sgtitle(sprintf("%s, %d retained directions", ...
        upsamplers(iMethod).name, sampling(iCondition).retentionCount), ...
        "Interpreter", "none");

    exportgraphics(fig, fullfile(cfg.resultsRoot, "spatial_fisher_maps.png"), ...
        "Resolution", 220);
    close(fig);

end

function plot_streaming_spatial_fisher_maps(representative, cfg)
% Plot the retained representative row recorded by the streaming run.

    assert(isfield(representative, "result") && ...
        representative.result.status == "completed", ...
        "Representative streaming plotting condition is not available.");
    result = representative.result;
    target = representative.target;
    azEl = plotting_azimuth_elevation(target.azElDeg);
    values = {result.airmByDirection, result.determinantErrorByDirection, ...
        result.anisotropyErrorByDirection, ...
        rad2deg(result.orientationErrorByDirection)};
    titles = {"AIRM distance", "Determinant error", ...
        "Anisotropy error", "Orientation error (deg)"};

    fig = figure("Visible", char(cfg.plots.visible), "Color", "w", ...
        "Name", "Spatial Fisher maps");
    tiledlayout(fig, 2, 2, "Padding", "compact", "TileSpacing", "compact");
    for iPanel = 1:numel(values)
        nexttile;
        scatter(azEl(:, 1), azEl(:, 2), 24, values{iPanel}, "filled");
        xlabel("Azimuth (deg)");
        ylabel("Elevation (deg)");
        title(titles{iPanel});
        xlim([-180, 180]);
        ylim([-90, 90]);
        grid on;
        colorbar;
    end
    colormap(fig, turbo);
    sgtitle(sprintf("%s, %d retained directions", ...
        representative.methodName, representative.retentionCount), ...
        "Interpreter", "none");
    exportgraphics(fig, fullfile(cfg.resultsRoot, "spatial_fisher_maps.png"), ...
        "Resolution", 220);
    close(fig);

end

function plot_maa_ellipse_fields(dataset, evaluationIndices, upsamplers, ...
        sampling, fisherResults, cfg)
% Draw local CRB/MAA ellipse fields from the target and reconstructed FIMs.

    [iCondition, iMethod] = selected_plot_condition(upsamplers, sampling, cfg);
    result = fisherResults(1, iCondition, iMethod);
    target = dataset(evaluationIndices(1));
    azEl = plotting_azimuth_elevation(target.azElDeg);

    numberToPlot = min(cfg.plots.maxEllipseDirections, size(target.r, 1));
    ellipseIndices = farthest_point_order(target.r, numberToPlot, cfg);

    fig = figure("Visible", char(cfg.plots.visible), "Color", "w", ...
        "Name", "MAA ellipse fields");
    tiledlayout(fig, 1, 2, "Padding", "compact", "TileSpacing", "compact");

    axesTarget = nexttile;
    plot_tensor_ellipse_panel(axesTarget, target.r, azEl, result.targetTensor, ...
        result.airmByDirection, ellipseIndices, cfg, "Reference Fisher field");

    axesRecon = nexttile;
    plot_tensor_ellipse_panel(axesRecon, target.r, azEl, ...
        result.reconstructedTensor, result.airmByDirection, ellipseIndices, ...
        cfg, "Reconstructed Fisher field");

    colormap(fig, turbo);
    sgtitle(sprintf("CRB/MAA ellipses: %s, %d retained directions", ...
        upsamplers(iMethod).name, sampling(iCondition).retentionCount), ...
        "Interpreter", "none");

    exportgraphics(fig, fullfile(cfg.resultsRoot, "maa_ellipse_fields.png"), ...
        "Resolution", 220);
    close(fig);

end

function plot_streaming_maa_ellipse_fields(representative, cfg)
% Draw the reference and reconstructed tensor fields retained in checkpoint.

    assert(isfield(representative, "result") && ...
        representative.result.status == "completed", ...
        "Representative streaming plotting condition is not available.");
    result = representative.result;
    target = representative.target;
    azEl = plotting_azimuth_elevation(target.azElDeg);
    numberToPlot = min(cfg.plots.maxEllipseDirections, size(target.r, 1));
    ellipseIndices = farthest_point_order(target.r, numberToPlot, cfg);

    fig = figure("Visible", char(cfg.plots.visible), "Color", "w", ...
        "Name", "MAA ellipse fields");
    tiledlayout(fig, 1, 2, "Padding", "compact", "TileSpacing", "compact");
    axesTarget = nexttile;
    plot_tensor_ellipse_panel(axesTarget, target.r, azEl, result.targetTensor, ...
        result.airmByDirection, ellipseIndices, cfg, "Reference Fisher field");
    axesRecon = nexttile;
    plot_tensor_ellipse_panel(axesRecon, target.r, azEl, ...
        result.reconstructedTensor, result.airmByDirection, ellipseIndices, ...
        cfg, "Reconstructed Fisher field");
    colormap(fig, turbo);
    sgtitle(sprintf("CRB/MAA ellipses: %s, %d retained directions", ...
        representative.methodName, representative.retentionCount), ...
        "Interpreter", "none");
    exportgraphics(fig, fullfile(cfg.resultsRoot, "maa_ellipse_fields.png"), ...
        "Resolution", 220);
    close(fig);

end

function plot_tensor_ellipse_panel(ax, r, azEl, tensors, colorValues, ...
        ellipseIndices, cfg, titleText)

    axes(ax);
    scatter(ax, azEl(:, 1), azEl(:, 2), 12, colorValues, "filled");
    hold(ax, "on");

    for iIndex = 1:numel(ellipseIndices)
        index = ellipseIndices(iIndex);
        curve = tensor_ellipse_curve(r(index, :).', tensors(:, :, index), cfg);
        if isempty(curve)
            continue;
        end
        plot(ax, curve(:, 1), curve(:, 2), "k-", "LineWidth", 0.7);
    end

    xlabel(ax, "Azimuth (deg)");
    ylabel(ax, "Elevation (deg)");
    title(ax, titleText);
    xlim(ax, [-180, 180]);
    ylim(ax, [-90, 90]);
    grid(ax, "on");
    colorbar(ax);

end

function curve = tensor_ellipse_curve(r, tensor, cfg)

    tensor = symmetrise(tensor);
    [principalDirections, information] = eig(tensor, "vector");
    [information, order] = sort(information, "descend");
    principalDirections = principalDirections(:, order);
    if min(information) <= cfg.informationFloor
        curve = [];
        return;
    end

    radii = cfg.plots.ellipseScale ./ sqrt(information);
    radii = min(radii, deg2rad(cfg.plots.maxEllipseRadiusDeg));
    theta = linspace(0, 2 * pi, 42);
    tangentOffsets = principalDirections * ...
        (radii .* [cos(theta); sin(theta)]);
    tangentBasis = local_tangent_basis(r);
    offsets = tangentBasis * tangentOffsets;
    curveR = zeros(numel(theta), 3);

    for iPoint = 1:numel(theta)
        distance = norm(offsets(:, iPoint));
        if distance < eps
            curveR(iPoint, :) = r.';
        else
            curveR(iPoint, :) = (cos(distance) * r + ...
                sin(distance) * offsets(:, iPoint) / distance).';
        end
    end

    curve = plotting_azimuth_elevation(cartesian_to_az_el(curveR));
    jumps = [false; abs(diff(curve(:, 1))) > 180];
    curve(jumps, :) = NaN;

end

function plot_perceptual_metrics(summary, cfg)
% Plot absolute observer outputs and, when requested, dense-self degradation.

    valid = summary.perceptualStatus == "completed";
    if ~any(valid)
        return;
    end

    evaluated = summary(valid, :);
    plot_perceptual_metric_figure(evaluated, ...
        ["lateralRMSErrorDeg", "localPolarRMSErrorDeg", ...
        "quadrantErrorPercent"], ...
        ["Lateral RMS error (deg)", "Local polar RMS error (deg)", ...
        "Quadrant error (%)"], ...
        sprintf("Barumerli absolute model outputs (%d trials)", ...
        cfg.perceptual.numExperiments), ...
        fullfile(cfg.resultsRoot, "barumerli_metrics.png"), cfg);

    if cfg.perceptual.reportRelativeToSelf && cfg.perceptual.plotRelativeToSelf && ...
            ismember("relativeLateralRMSErrorDeg", ...
            string(evaluated.Properties.VariableNames)) && ...
            any(~isnan(evaluated.relativeLateralRMSErrorDeg))
        plot_perceptual_metric_figure(evaluated, ...
            ["relativeLateralRMSErrorDeg", ...
            "relativeLocalPolarRMSErrorDeg", ...
            "relativeQuadrantErrorPercentagePoints"], ...
            ["Relative lateral RMS (deg)", "Relative local polar RMS (deg)", ...
            "Relative quadrant error (percentage points)"], ...
            sprintf("Barumerli degradation relative to dense self (%d trials)", ...
            cfg.perceptual.numExperiments), ...
            fullfile(cfg.resultsRoot, ...
            "barumerli_metrics_relative_to_self.png"), cfg);
    end

end

function plot_perceptual_metric_figure( ...
        evaluated, metricNames, axisLabels, titleText, outputPath, cfg)

    fig = figure("Visible", char(cfg.plots.visible), "Color", "w", ...
        "Name", "Barumerli perceptual metrics");
    tiledlayout(fig, 1, 3, "Padding", "compact", "TileSpacing", "compact");
    for iMetric = 1:numel(metricNames)
        plot_metric_by_condition(evaluated, metricNames(iMetric), ...
            axisLabels(iMetric));
    end
    sgtitle(titleText);

    exportgraphics(fig, outputPath, "Resolution", 220);
    close(fig);

end

function plot_metric_by_condition(summary, variableName, axisLabel)

    nexttile;
    hold on;
    methods = unique(summary.method, "stable");
    conditions = sort(unique(summary.retainedDirections));
    colors = lines(numel(methods));
    for iMethod = 1:numel(methods)
        meanMetric = nan(size(conditions));
        standardError = nan(size(conditions));
        for iCondition = 1:numel(conditions)
            idx = summary.method == methods(iMethod) & ...
                summary.retainedDirections == conditions(iCondition);
            values = summary.(variableName)(idx);
            meanMetric(iCondition) = mean(values, "omitnan");
            validValues = values(~isnan(values));
            if numel(validValues) > 1
                standardError(iCondition) = std(validValues) / ...
                    sqrt(numel(validValues));
            else
                standardError(iCondition) = 0;
            end
        end
        errorbar(conditions, meanMetric, standardError, "-o", ...
            "LineWidth", 1.1, "Color", colors(iMethod, :), ...
            "DisplayName", methods(iMethod));
    end
    xlabel("Retained directions");
    ylabel(axisLabel);
    grid on;
    legend("Location", "best", "Interpreter", "none");

end

function [iCondition, iMethod] = selected_plot_condition( ...
        upsamplers, sampling, cfg)

    methodNames = string({upsamplers.name});
    iMethod = find(methodNames == cfg.plots.representativeMethod, 1, "first");
    retentionCounts = [sampling.retentionCount];
    iCondition = find(retentionCounts == cfg.plots.representativeRetention, ...
        1, "first");
    assert(~isempty(iMethod) && ~isempty(iCondition), ...
        "Configured representative plot method/retention is absent.");

end

function azEl = plotting_azimuth_elevation(azEl)

    azEl(:, 1) = mod(azEl(:, 1) + 180, 360) - 180;

end





