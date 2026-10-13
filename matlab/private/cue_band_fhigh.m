function fhigh = cue_band_fhigh(cfg)
% Upper gammatone centre frequency for Barumerli feature extraction.

    if isfinite(cfg.cueBand.limitHz)
        fhigh = cfg.cueBand.limitHz;
    else
        fhigh = 18e3;                % AMT barumerli2023 default
    end

end
