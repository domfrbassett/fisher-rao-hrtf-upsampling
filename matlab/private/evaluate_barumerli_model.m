function result = evaluate_barumerli_model(referenceTemplate, target, recon, cfg, targetFeatures)
% Evaluate one reconstruction as a Barumerli target stimulus while the
% measured HRTF supplies the fixed internal template.

    if nargin < 5 || isempty(fieldnames(targetFeatures))
        reconstructedDtf = convert_field_to_dtf_sofa(recon, target, cfg);
        targetFeatures = barumerli2023_featureextraction(reconstructedDtf, ...
            'target', char(cfg.perceptual.featureSpace), ...
            'fhigh', cue_band_fhigh(cfg));
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
