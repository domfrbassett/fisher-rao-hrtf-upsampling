function audit = run_adaptive_2ifc_export_and_build(projectRoot, skipExport)
%RUN_ADAPTIVE_2IFC_EXPORT_AND_BUILD Create the adaptive listening-test bank.
%
% This function expects the caller to set the evaluation environment
% variables, in particular FISHER_RAO_BEHAVIOURAL_EXPORT_ONLY=true and the
% Hu/LAP comparator protocol path. The wrapper script in the project root
% sets those values for the standard study configuration.

    arguments
        projectRoot (1, 1) string = string(fileparts(fileparts(fileparts(mfilename("fullpath")))))
        skipExport (1, 1) logical = false
    end

    studyRoot = fullfile(projectRoot, "listening_test");
    publicRoot = fullfile(studyRoot, "public");
    matlabRoot = fullfile(studyRoot, "matlab");

    addpath(char(projectRoot), "-begin");
    addpath(char(matlabRoot), "-begin");

    if ~skipExport
        run(fullfile(projectRoot, "run_hrtf_fisher_rao_evaluation.m"));
    end

    % The evaluator is a script and deliberately starts with clear; rebuild
    % wrapper paths after it returns.
    projectRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
    studyRoot = fullfile(projectRoot, "listening_test");
    publicRoot = fullfile(studyRoot, "public");
    matlabRoot = fullfile(studyRoot, "matlab");
    addpath(char(matlabRoot), "-begin");

    renderInterpolation = string(getenv("FISHERRAO_ADAPTIVE_RENDER_INTERPOLATION"));
    if strlength(renderInterpolation) == 0
        renderInterpolation = "StoredGridOnly";
    end
    snapTargetsToGrid = renderInterpolation == "StoredGridOnly";
    manifestVersion = "adaptive-v4-grid-native-balanced-subjects";
    lateralLevels = [30, 20, 15, 10, 5];
    polarLevels = [30, 20, 15, 10, 5];
    if renderInterpolation == "LocalMinimumPhaseDelayIDW"
        manifestVersion = "adaptive-v3-minphase-delay-idw-floorstop";
        lateralLevels = [30, 20, 15, 10, 7, 5, 3.5, 2.5, 1.75, 1.25];
        polarLevels = [30, 20, 15, 10, 7, 5, 3.5, 2.5];
    elseif renderInterpolation ~= "StoredGridOnly"
        manifestVersion = "adaptive-v5-subgrid-supdeq-raw-ml";
        lateralLevels = [30, 20, 15, 10, 7, 5, 3.5, 2.5, 1.75, 1.25];
        polarLevels = [30, 20, 15, 10, 7, 5, 3.5, 2.5];
    end

    plan = generate_adaptive_condition_plan(studyRoot, ...
        "snapTargetsToGrid", snapTargetsToGrid, ...
        "lateralAngularLevelsDeg", lateralLevels, ...
        "polarAngularLevelsDeg", polarLevels); %#ok<NASGU>
    manifest = build_adaptive_2ifc_stimulus_bank( ...
        fullfile(matlabRoot, "adaptive_condition_plan.csv"), publicRoot, ...
        "manifestVersion", manifestVersion, ...
        "renderInterpolation", renderInterpolation); %#ok<NASGU>

    audit = audit_adaptive_2ifc_stimulus_bank( ...
        fullfile(publicRoot, "config", "trials.adaptive.json"), publicRoot);
    writetable(audit, fullfile(publicRoot, "config", ...
        "adaptive_rendered_wav_audit.csv"));
    write_adaptive_experiment_config(publicRoot, manifestVersion);

end

function write_adaptive_experiment_config(publicRoot, manifestVersion)
    config = struct();
    config.studyId = "fisher_rao_hrtf_2ifc";
    config.title = "Spatial Direction Discrimination";
    config.manifest = "config/trials.adaptive.json";
    config.manifestVersion = char(manifestVersion);
    config.mode = "adaptive";
    config.intervalGapMs = 400;
    config.interTrialPauseMs = 150;
    config.calibrationDurationMs = 650;
    config.calibrationLevel = 0.12;

    path = fullfile(publicRoot, "config", "experiment.adaptive.json");
    fid = fopen(path, "w");
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, "%s\n", jsonencode(config, "PrettyPrint", true));
    clear cleanup;
end
