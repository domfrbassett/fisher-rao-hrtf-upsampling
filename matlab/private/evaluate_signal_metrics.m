function signal = evaluate_signal_metrics(target, recon, cfg)

    if recon.isAvailable
        signal.LSD = compute_binaural_lsd(target.hrir, recon.hrir, target.fs, cfg);
        signal.ILD = compute_ild_error(target.hrir, recon.hrir, cfg);
        signal.LSD16k = compute_binaural_lsd(target.hrir, recon.hrir, ...
            target.fs, cfg, cfg.signalBandHz);
        signal.ILD16k = compute_ild_error( ...
            apply_cue_band_limit(target.hrir, target.fs, cfg), ...
            apply_cue_band_limit(recon.hrir, recon.fs, cfg), cfg);
        signal.status = "completed";
        signal.message = "";
    else
        signal.LSD = NaN;
        signal.ILD = NaN;
        signal.LSD16k = NaN;
        signal.ILD16k = NaN;
        signal.status = "not_applicable";
        signal.message = recon.message;
    end

end

function lsd = compute_binaural_lsd(targetHrir, reconHrir, fs, cfg, bandHz)
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
    if nargin < 5
        bandHz = [20, 20000];
    end
    nSamples = max(size(targetHrir, 3), size(reconHrir, 3));
    nPositive = floor(nSamples / 2);
    freqs = (0:(nPositive - 1)) * fs / nSamples;
    freqIdx = freqs >= bandHz(1) & freqs <= bandHz(2);
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
