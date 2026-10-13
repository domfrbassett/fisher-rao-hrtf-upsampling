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
    assert(all(isfinite(field.hrir), "all"), ...
        "Non-finite HRIR samples reached Barumerli feature extraction.");
    sofa.Data.IR = apply_cue_band_limit(real(field.hrir), field.fs, cfg);
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
