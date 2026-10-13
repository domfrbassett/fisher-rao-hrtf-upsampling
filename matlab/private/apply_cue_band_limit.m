function hrir = apply_cue_band_limit(hrir, fs, cfg)
% Common linear-phase low-pass applied to every field before cue
% extraction. The HRIR is zero-padded by the filter order so the delayed
% tail is retained; the constant group delay (order/2 samples) is common to
% both ears and all directions.

    if ~isfinite(cfg.cueBand.limitHz) || cfg.cueBand.limitHz >= fs / 2
        return;
    end
    order = cfg.cueBand.firOrder;
    b = fir1(order, cfg.cueBand.firCutoffHz / (fs / 2), ...
        kaiser(order + 1, cfg.cueBand.kaiserBeta));
    padded = cat(3, hrir, zeros(size(hrir, 1), size(hrir, 2), order, ...
        "like", hrir));
    hrir = filter(b, 1, padded, [], 3);

end
