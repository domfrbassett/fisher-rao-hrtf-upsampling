function summary = run_fisher_rao_evaluation(cfg)
% RUN_FISHER_RAO_EVALUATION  Evaluate every subject x retention x method row
% of the comparator protocol:
%   - signal metrics (LSD, ILD error)
%   - Fisher tensors of the reference and reconstructed cue fields and their
%     AIRM discrepancy (tensor files written per row)
%   - the Barumerli (2023) Bayesian observer, if cfg.runPerceptualModel
%
% cfg comes from fisher_rao_config. Rows are evaluated one at a time and
% checkpointed in cfg.resultsRoot, so an interrupted run resumes where it
% stopped. Helpers are in matlab/private/ (see matlab/README.md).

    rng(cfg.randomSeed);
    configure_toolbox_paths(cfg);
    verify_configured_dependencies(cfg);

    % Load the first subject now; the run loop loads one subject at a time.
    seedCfg = cfg;
    seedCfg.subjectIds = cfg.validationIds(1);
    dataset = load_dense_hrtf_dataset(seedCfg);
    dataset = preprocess_hrtf_dataset(dataset, cfg);

    upsamplers = initialise_upsampling_methods(cfg);
    sampling = create_sampling_conditions(dataset, cfg);

    summary = run_streaming_evaluation(dataset, upsamplers, sampling, cfg);
    fprintf("Evaluated %d rows; summary: %s\n", height(summary), ...
        cfg.execution.summaryCsv);

end
