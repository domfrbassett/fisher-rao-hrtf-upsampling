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
