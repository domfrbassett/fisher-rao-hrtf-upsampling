function template = create_barumerli_template(target, cfg)
% Generate the model's internal template from the measured reference DTFs.

    referenceDtf = convert_field_to_dtf_sofa(target, target, cfg);
    template = barumerli2023_featureextraction(referenceDtf, ...
        'template', char(cfg.perceptual.featureSpace), ...
        'fhigh', cue_band_fhigh(cfg));

end
