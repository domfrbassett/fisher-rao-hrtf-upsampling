function import_ranf_raw_sofas_for_behavioural_fields(projectRoot, rawExperimentRoot, subjectIds, retentions)
%IMPORT_RANF_RAW_SOFAS_FOR_BEHAVIOURAL_FIELDS Convert raw RANF SOFAs to field mats.

    arguments
        projectRoot (1, 1) string = string(fileparts(fileparts(fileparts(mfilename("fullpath")))))
        rawExperimentRoot (1, 1) string = fullfile(projectRoot, ...
            "ml_comparator_research", "comparator_protocol", "work", ...
            "ranf_sonicom", "experiments")
        subjectIds (1, :) double = [33]
        retentions (1, :) double = [5, 19]
    end

    ensure_sofa_paths(projectRoot);
    fieldsRoot = fullfile(projectRoot, "listening_test", "fields");

    for iRetention = 1:numel(retentions)
        retention = retentions(iRetention);
        sourceFolder = fullfile(rawExperimentRoot, ...
            sprintf("ranf_hu_N%03d", retention), "log", ...
            "eval_raw_no_node_replacement");
        assert(isfolder(sourceFolder), ...
            "Raw RANF export folder does not exist: %s", sourceFolder);

        for iSubject = 1:numel(subjectIds)
            subjectId = subjectIds(iSubject);
            sofaPath = fullfile(sourceFolder, sprintf("pred_p%04d.sofa", subjectId));
            assert(isfile(sofaPath), "Missing raw RANF SOFA: %s", sofaPath);

            field = read_sofa_field_for_behavioural_export(sofaPath);
            field.method = "RANF_raw";
            field.retainedDirections = retention;
            field.sourceSofaPath = string(sofaPath);
            field.provenance = "RANF raw inference SOFA without retained-node replacement";

            subjectFolder = fullfile(fieldsRoot, sprintf("subject_%04d", subjectId));
            if ~isfolder(subjectFolder)
                mkdir(subjectFolder);
            end
            outPath = fullfile(subjectFolder, ...
                sprintf("RANF_raw_N%03d_hrir_field.mat", retention));
            save(outPath, "field", "-v7.3");
            fprintf("Wrote %s\n", outPath);
        end
    end
end

function ensure_sofa_paths(projectRoot)

    dependencyRoot = fullfile(projectRoot, "dependencies");
    sofaRoot = fullfile(dependencyRoot, ...
        "SOFA Toolbox for Matlab and Octave 2.2.0", "SOFAtoolbox");
    assert(isfolder(sofaRoot), "SOFA Toolbox folder not found: %s", sofaRoot);
    addpath(genpath(char(sofaRoot)));

end

function field = read_sofa_field_for_behavioural_export(sofaPath)

    sofa = SOFAload(char(sofaPath));
    hrir = double(sofa.Data.IR);
    fs = double(sofa.Data.SamplingRate(1));
    [r, azElDeg] = sofa_positions_to_cartesian_az_el(sofa);

    if isfield(sofa.Data, "Delay") && ...
            size(sofa.Data.Delay, 1) == size(hrir, 1) && ...
            any(abs(double(sofa.Data.Delay(:))) > eps)
        hrir = apply_sofa_delay(hrir, double(sofa.Data.Delay), fs);
    end

    fftLength = max(256, 2 ^ nextpow2(size(hrir, 3)));
    spectrum = fft(hrir, fftLength, 3);
    complexHrtf = permute(spectrum(:, :, 1:(fftLength / 2 + 1)), [1, 3, 2]);

    field = struct();
    field.hrir = hrir;
    field.fs = fs;
    field.r = r;
    field.azElDeg = azElDeg;
    field.fftLength = fftLength;
    field.complexHrtf = complexHrtf;
    field.freqHzWithDC = linspace(0, fs / 2, fftLength / 2 + 1);

end

function [r, azElDeg] = sofa_positions_to_cartesian_az_el(sofa)

    positions = double(sofa.SourcePosition);
    azimuth = positions(:, 1);
    elevation = positions(:, 2);
    radius = ones(size(azimuth));
    if size(positions, 2) >= 3
        radius = positions(:, 3);
        radius(radius == 0) = 1;
    end
    [x, y, z] = sph2cart(deg2rad(azimuth), deg2rad(elevation), radius);
    r = [x, y, z];
    r = r ./ vecnorm(r, 2, 2);
    azElDeg = [mod(azimuth + 180, 360) - 180, elevation];

end

function shifted = apply_sofa_delay(hrir, delay, fs)

    shifted = zeros(size(hrir));
    nSamples = size(hrir, 3);
    delaySamples = round(delay .* fs);
    for iDirection = 1:size(hrir, 1)
        for iEar = 1:size(hrir, 2)
            shift = delaySamples(iDirection, iEar);
            signal = squeeze(hrir(iDirection, iEar, :)).';
            if shift > 0
                shifted(iDirection, iEar, :) = [zeros(1, shift), ...
                    signal(1:(nSamples - shift))];
            elseif shift < 0
                shift = abs(shift);
                shifted(iDirection, iEar, :) = [signal((shift + 1):end), ...
                    zeros(1, shift)];
            else
                shifted(iDirection, iEar, :) = signal;
            end
        end
    end

end
