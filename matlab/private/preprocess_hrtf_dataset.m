function dataset = preprocess_hrtf_dataset(dataset, cfg)
% Form the spectra used by both the SUpDEq adapter and the subsequent
% signal/Fisher evaluations. The measured HRIRs are used unwindowed.

    for iSubject = 1:numel(dataset)

        processedField = refresh_field_spectra(dataset(iSubject), cfg);
        dataset(iSubject).complexHrtf = processedField.complexHrtf;
        dataset(iSubject).hrtfMag = processedField.hrtfMag;
        dataset(iSubject).freqHzWithDC = processedField.freqHzWithDC;
        dataset(iSubject).freqHz = processedField.freqHz;

    end

end
