function manifest = build_adaptive_2ifc_stimulus_bank(conditionPlanCsv, publicRoot, cfg)
%BUILD_ADAPTIVE_2IFC_STIMULUS_BANK Render WAVs for adaptive 2AFC tracks.
%
% Each row of conditionPlanCsv defines one angular separation level within
% an adaptive track. Rows with the same trackId are grouped into one
% staircase. The browser first descends quickly through easy levels, then
% switches to a two-down/one-up rule after the first reversal; no convolution
% or spatialisation is performed during the participant session.

    arguments
        conditionPlanCsv (1, 1) string
        publicRoot (1, 1) string
        cfg.studyId (1, 1) string = "fisher_rao_hrtf_2ifc"
        cfg.manifestVersion (1, 1) string = "adaptive-v4-grid-native-balanced-subjects"
        cfg.outputManifestName (1, 1) string = "trials.adaptive.json"
        cfg.sampleRate (1, 1) double = 48000
        cfg.durationSeconds (1, 1) double = 0.65
        cfg.rampSeconds (1, 1) double = 0.02
        cfg.noiseSeed (1, 1) double = 20260624
        cfg.levelRoveDb (1, 1) double = 1.5
        cfg.targetPeak (1, 1) double = 0.18
        cfg.startLevelIndex (1, 1) double = 1
        cfg.minTrials (1, 1) double = 14
        cfg.maxTrials (1, 1) double = 24
        cfg.reversalsToStop (1, 1) double = 6
        cfg.floorMinTrials (1, 1) double = 8
        cfg.floorAccuracyToStop (1, 1) double = 0.875
        cfg.correctToDescend (1, 1) double = 2
        cfg.correctToDescendBeforeFirstReversal (1, 1) double = 1
        cfg.tracksPerBlock (1, 1) double = 8
        cfg.barycentricTolerance (1, 1) double = 1e-7
        cfg.renderInterpolation (1, 1) string = "StoredGridOnly"
        cfg.headRadius (1, 1) double = 0.0875
        cfg.supdeqMaxSHOrder (1, 1) double = 27
        cfg.supdeqTikhEps (1, 1) double = 0
        cfg.supdeqMcDb (1, 1) double = 6
        cfg.supdeqLimitMC (1, 1) logical = true
        cfg.supdeqMcKnee (1, 1) double = 0
        cfg.supdeqMcMinPhase (1, 1) logical = true
        cfg.supdeqLimFade (1, 1) string = "fadeDown"
    end

    plan = readtable(conditionPlanCsv, "TextType", "string");
    required = ["trackId", "blockId", "blockLabel", "blockType", "axis", ...
        "question", "virtualHrtfSubjectId", "fieldType", "method", ...
        "retainedDirections", "fieldMat", "referenceMetricTensorMat", ...
        "fieldMetricTensorMat", "anchorId", "levelIndex", "separationDeg", ...
        "standardIndex", "targetIndex", "targetOppositeIndex", ...
        "standardX", "standardY", "standardZ", "targetX", "targetY", "targetZ", ...
        "targetOppositeX", "targetOppositeY", "targetOppositeZ", ...
        "LSDdB", "ILDErrorDb"];
    missing = setdiff(required, string(plan.Properties.VariableNames));
    assert(isempty(missing), "Adaptive condition plan missing columns: %s", ...
        strjoin(missing, ", "));

    audioRoot = fullfile(publicRoot, "audio", "adaptive");
    configRoot = fullfile(publicRoot, "config");
    ensure_folder(audioRoot);
    ensure_folder(configRoot);
    clear_existing_adaptive_wavs(audioRoot);
    if uses_supdeq_renderer(cfg.renderInterpolation)
        ensure_supdeq_renderer_paths(publicRoot);
    end

    stream = RandStream("mt19937ar", "Seed", cfg.noiseSeed);
    [standardHrirs, targetHrirs, oppositeTargetHrirs] = ...
        precompute_interpolated_hrirs(plan, cfg);
    levelRecords = repmat(empty_level_record(), height(plan), 1);

    for iRow = 1:height(plan)
        field = load_hrir_field(plan.fieldMat(iRow));
        assert(field.fs == cfg.sampleRate, ...
            "Field sampling rate must be %d Hz for adaptive bank.", cfg.sampleRate);

        standardIndex = plan.standardIndex(iRow);
        targetIndex = plan.targetIndex(iRow);
        targetOppositeIndex = plan.targetOppositeIndex(iRow);
        standardDirection = normalise([plan.standardX(iRow); ...
            plan.standardY(iRow); plan.standardZ(iRow)]);
        targetDirection = normalise([plan.targetX(iRow); ...
            plan.targetY(iRow); plan.targetZ(iRow)]);
        targetOppositeDirection = normalise([plan.targetOppositeX(iRow); ...
            plan.targetOppositeY(iRow); plan.targetOppositeZ(iRow)]);
        standardHrir = standardHrirs{iRow};
        targetHrir = targetHrirs{iRow};
        oppositeTargetHrir = oppositeTargetHrirs{iRow};

        tokenSeed = deterministic_seed(plan.trackId(iRow), plan.levelIndex(iRow), ...
            cfg.noiseSeed);
        source = broadband_token(tokenSeed, cfg);
        standardAudio = render_binaural_source(source, standardHrir);
        targetAudio = render_binaural_source(source, targetHrir);
        oppositeTargetAudio = render_binaural_source(source, oppositeTargetHrir);
        [standardAudio, targetAudio, oppositeTargetAudio] = normalise_group( ...
            standardAudio, targetAudio, oppositeTargetAudio, cfg);
        rove = ((2 * rand(stream) - 1) * cfg.levelRoveDb);
        standardAudio = standardAudio .* 10 ^ (rove / 20);
        targetAudio = targetAudio .* 10 ^ (rove / 20);
        oppositeTargetAudio = oppositeTargetAudio .* 10 ^ (rove / 20);

        safeId = regexprep(sprintf("%s_L%02d", char(plan.trackId(iRow)), ...
            plan.levelIndex(iRow)), "[^A-Za-z0-9_-]", "_");
        standardName = sprintf("%s_standard.wav", safeId);
        targetName = sprintf("%s_target.wav", safeId);
        oppositeTargetName = sprintf("%s_target_opposite.wav", safeId);
        audiowrite(fullfile(audioRoot, standardName), standardAudio, cfg.sampleRate, ...
            "BitsPerSample", 24);
        audiowrite(fullfile(audioRoot, targetName), targetAudio, cfg.sampleRate, ...
            "BitsPerSample", 24);
        audiowrite(fullfile(audioRoot, oppositeTargetName), oppositeTargetAudio, ...
            cfg.sampleRate, "BitsPerSample", 24);

        [referenceTensor, tensorCoordinates] = load_metric_tensor( ...
            plan.referenceMetricTensorMat(iRow));
        [fieldTensor, fieldTensorCoordinates] = load_metric_tensor( ...
            plan.fieldMetricTensorMat(iRow));
        assert_grid_agreement(field.r, tensorCoordinates);
        assert_grid_agreement(tensorCoordinates, fieldTensorCoordinates);
        metric = pair_metric_predictions(referenceTensor, fieldTensor, ...
            tensorCoordinates, standardDirection, targetDirection);

        record = empty_level_record();
        record.levelIndex = plan.levelIndex(iRow);
        record.separationDeg = plan.separationDeg(iRow);
        record.standardIndex = standardIndex;
        record.targetIndex = targetIndex;
        record.targetOppositeIndex = targetOppositeIndex;
        record.standardDirection = standardDirection.';
        record.targetDirection = targetDirection.';
        record.targetOppositeDirection = targetOppositeDirection.';
        record.localAIRM = metric.localAIRM;
        record.predictedDPrimeReference = metric.predictedDPrimeReference;
        record.predictedDPrimeField = metric.predictedDPrimeField;
        record.LSDdB = plan.LSDdB(iRow);
        record.ILDErrorDb = plan.ILDErrorDb(iRow);
        record.stimuli.standard = struct("type", "wav", ...
            "url", sprintf("audio/adaptive/%s", standardName));
        record.stimuli.target = struct("type", "wav", ...
            "url", sprintf("audio/adaptive/%s", targetName));
        record.stimuli.targetOpposite = struct("type", "wav", ...
            "url", sprintf("audio/adaptive/%s", oppositeTargetName));
        levelRecords(iRow) = record;
    end

    manifest.studyId = char(cfg.studyId);
    manifest.manifestVersion = char(cfg.manifestVersion);
    manifest.mode = "adaptive";
    if cfg.renderInterpolation == "StoredGridOnly"
        manifest.notice = "Adaptive 2AFC staircases using stored-grid stereo WAV levels.";
    else
        manifest.notice = sprintf( ...
            "Adaptive 2AFC staircases using %s continuous-rendered stereo WAV levels.", ...
            cfg.renderInterpolation);
    end
    manifest.renderInterpolation = char(cfg.renderInterpolation);
    manifest.virtualSubjectAssignment = "mixed_representative_subjects_within_participant";
    manifest.virtualHrtfSubjectIds = unique(plan.virtualHrtfSubjectId, "stable").';
    manifest.adaptiveRule = struct("rule", "two-down-one-up", ...
        "targetPc", 0.707, "startLevelIndex", cfg.startLevelIndex - 1, ...
        "minTrials", cfg.minTrials, "maxTrials", cfg.maxTrials, ...
        "reversalsToStop", cfg.reversalsToStop, ...
        "floorMinTrials", cfg.floorMinTrials, ...
        "floorAccuracyToStop", cfg.floorAccuracyToStop, ...
        "correctToDescend", cfg.correctToDescend, ...
        "correctToDescendBeforeFirstReversal", ...
        cfg.correctToDescendBeforeFirstReversal);

    blockIds = unique(plan.blockId, "stable");
    manifest.blocks = repmat(empty_block_record(), 0, 1);
    for iBlock = 1:numel(blockIds)
        blockRows = find(plan.blockId == blockIds(iBlock));
        baseBlockId = char(blockIds(iBlock));
        baseBlockLabel = char(plan.blockLabel(blockRows(1)));
        axisName = char(plan.axis(blockRows(1)));
        if plan.axis(blockRows(1)) == "lateral"
            instruction = "Attend only to left-right position.";
        else
            instruction = "Attend only to vertical position.";
        end

        trackIds = unique(plan.trackId(blockRows), "stable");
        trackRecords = repmat(empty_track_record(), numel(trackIds), 1);
        for iTrack = 1:numel(trackIds)
            rows = blockRows(plan.trackId(blockRows) == trackIds(iTrack));
            [~, order] = sort(plan.separationDeg(rows), "descend");
            rows = rows(order);
            track = empty_track_record();
            first = rows(1);
            track.trackId = char(trackIds(iTrack));
            track.pairId = char(plan.anchorId(first));
            track.anchorId = char(plan.anchorId(first));
            track.virtualHrtfSubjectId = plan.virtualHrtfSubjectId(first);
            track.fieldType = char(plan.fieldType(first));
            track.method = char(plan.method(first));
            track.retainedDirections = plan.retainedDirections(first);
            track.difficultySection = "adaptive";
            track.levels = levelRecords(rows);
            trackRecords(iTrack) = track;
        end

        sectionCount = max(1, ceil(numel(trackRecords) / cfg.tracksPerBlock));
        for iSection = 1:sectionCount
            sectionStart = (iSection - 1) * cfg.tracksPerBlock + 1;
            sectionEnd = min(iSection * cfg.tracksPerBlock, numel(trackRecords));
            block = empty_block_record();
            if sectionCount == 1
                block.blockId = baseBlockId;
                block.label = baseBlockLabel;
                block.instruction = instruction;
            else
                block.blockId = sprintf("%s_part%02d", baseBlockId, iSection);
                block.label = sprintf("%s (%d/%d)", baseBlockLabel, ...
                    iSection, sectionCount);
                block.instruction = sprintf("%s This is section %d of %d.", ...
                    instruction, iSection, sectionCount);
            end
            block.type = char(plan.blockType(blockRows(1)));
            block.adaptive = true;
            block.adaptiveRule = manifest.adaptiveRule;
            block.axis = axisName;
            block.question = char(plan.question(blockRows(1)));
            block.tracks = trackRecords(sectionStart:sectionEnd);
            manifest.blocks(end + 1, 1) = block; %#ok<AGROW>
        end
    end

    outputPath = fullfile(configRoot, cfg.outputManifestName);
    fileId = fopen(outputPath, "w");
    assert(fileId ~= -1, "Unable to create adaptive trial manifest: %s", outputPath);
    cleanup = onCleanup(@() fclose(fileId));
    fprintf(fileId, "%s\n", jsonencode(manifest, "PrettyPrint", true));
    fprintf("Wrote %d adaptive tracks and %d levels to %s.\n", ...
        sum(arrayfun(@(b) numel(b.tracks), manifest.blocks)), height(plan), outputPath);

end

function clear_existing_adaptive_wavs(audioRoot)

    wavs = dir(fullfile(audioRoot, "*.wav"));
    for iFile = 1:numel(wavs)
        delete(fullfile(wavs(iFile).folder, wavs(iFile).name));
    end

end

function [standardHrirs, targetHrirs, oppositeTargetHrirs] = ...
        precompute_interpolated_hrirs(plan, cfg)

    standardHrirs = cell(height(plan), 1);
    targetHrirs = cell(height(plan), 1);
    oppositeTargetHrirs = cell(height(plan), 1);
    fieldFiles = unique(plan.fieldMat, "stable");
    for iField = 1:numel(fieldFiles)
        rows = find(plan.fieldMat == fieldFiles(iField));
        field = load_hrir_field(fieldFiles(iField));
        assert(field.fs == cfg.sampleRate, ...
            "Field sampling rate must be %d Hz for adaptive bank.", cfg.sampleRate);

        if cfg.renderInterpolation == "StoredGridOnly"
            for iRow = 1:numel(rows)
                row = rows(iRow);
                standardHrirs{row} = squeeze(field.hrir(plan.standardIndex(row), :, :));
                targetHrirs{row} = squeeze(field.hrir(plan.targetIndex(row), :, :));
                oppositeTargetHrirs{row} = squeeze( ...
                    field.hrir(plan.targetOppositeIndex(row), :, :));
            end
            fprintf("Loaded %s stored-grid HRIR levels for %s.\n", ...
                num2str(numel(rows)), fieldFiles(iField));
            continue;
        end

        standardDirections = [plan.standardX(rows), plan.standardY(rows), ...
            plan.standardZ(rows)];
        targetDirections = [plan.targetX(rows), plan.targetY(rows), ...
            plan.targetZ(rows)];
        if ismember("targetOppositeX", plan.Properties.VariableNames)
            oppositeTargetDirections = [plan.targetOppositeX(rows), ...
                plan.targetOppositeY(rows), plan.targetOppositeZ(rows)];
        else
            oppositeTargetDirections = opposite_target_directions( ...
                standardDirections, targetDirections);
        end
        requestedDirections = normalise_rows([standardDirections; ...
            targetDirections; oppositeTargetDirections]);
        [uniqueDirections, ~, directionMap] = unique_direction_rows( ...
            requestedDirections);

        hrirBank = interpolate_hrir_directions(field, uniqueDirections, cfg);
        for iRow = 1:numel(rows)
            standardHrirs{rows(iRow)} = squeeze(hrirBank(directionMap(iRow), :, :));
            targetHrirs{rows(iRow)} = squeeze(hrirBank(directionMap(iRow + numel(rows)), :, :));
            oppositeTargetHrirs{rows(iRow)} = squeeze( ...
                hrirBank(directionMap(iRow + 2 * numel(rows)), :, :));
        end
        fprintf("Rendered continuous %s HRIRs for %s using %s.\n", ...
            num2str(size(uniqueDirections, 1)), fieldFiles(iField), ...
            cfg.renderInterpolation);
    end

end

function oppositeDirections = opposite_target_directions(standardDirections, ...
        targetDirections)

    oppositeDirections = zeros(size(standardDirections));
    for iDirection = 1:size(standardDirections, 1)
        standard = normalise(standardDirections(iDirection, :).');
        target = normalise(targetDirections(iDirection, :).');
        displacement = sphere_log_map(standard, target);
        oppositeDirections(iDirection, :) = sphere_exp_map( ...
            standard, -displacement).';
    end

end

function [uniqueDirections, firstIndex, directionMap] = unique_direction_rows(directions)

    rounded = round(directions * 1e12) / 1e12;
    keyMap = containers.Map("KeyType", "char", "ValueType", "double");
    firstIndex = zeros(0, 1);
    directionMap = zeros(size(directions, 1), 1);
    for iDirection = 1:size(directions, 1)
        key = sprintf("%.12f_%.12f_%.12f", rounded(iDirection, 1), ...
            rounded(iDirection, 2), rounded(iDirection, 3));
        if isKey(keyMap, key)
            directionMap(iDirection) = keyMap(key);
        else
            firstIndex(end + 1, 1) = iDirection; %#ok<AGROW>
            directionMap(iDirection) = numel(firstIndex);
            keyMap(key) = numel(firstIndex);
        end
    end
    uniqueDirections = directions(firstIndex, :);

end

function track = empty_track_record()
    track = struct("trackId", "", "pairId", "", "anchorId", "", ...
        "virtualHrtfSubjectId", NaN, "fieldType", "", "method", "", ...
        "retainedDirections", NaN, "difficultySection", "", "levels", []);
end

function block = empty_block_record()
    block = struct("blockId", "", "label", "", "instruction", "", ...
        "type", "", "adaptive", true, "adaptiveRule", struct(), ...
        "axis", "", "question", "", "tracks", []);
end

function level = empty_level_record()
    level = struct("levelIndex", NaN, "separationDeg", NaN, ...
        "standardIndex", NaN, "targetIndex", NaN, ...
        "targetOppositeIndex", NaN, ...
        "standardDirection", [NaN, NaN, NaN], ...
        "targetDirection", [NaN, NaN, NaN], ...
        "targetOppositeDirection", [NaN, NaN, NaN], ...
        "localAIRM", NaN, "predictedDPrimeReference", NaN, ...
        "predictedDPrimeField", NaN, "LSDdB", NaN, "ILDErrorDb", NaN, ...
        "stimuli", struct("standard", struct(), "target", struct(), ...
        "targetOpposite", struct()));
end

function seed = deterministic_seed(trackId, levelIndex, baseSeed)
    text = char(trackId);
    seed = uint32(baseSeed);
    for iChar = 1:numel(text)
        seed = seed * uint32(1664525) + uint32(text(iChar)) + uint32(1013904223);
    end
    seed = double(mod(seed + uint32(levelIndex * 7919), uint32(2^31 - 1)));
end

function source = broadband_token(seed, cfg)
    stream = RandStream("mt19937ar", "Seed", double(seed));
    nSamples = round(cfg.durationSeconds * cfg.sampleRate);
    source = randn(stream, nSamples, 1);
    source = source ./ max(sqrt(mean(source .^ 2)), eps);
    nRamp = round(cfg.rampSeconds * cfg.sampleRate);
    ramp = 0.5 - 0.5 * cos(linspace(0, pi, nRamp).');
    window = ones(nSamples, 1);
    window(1:nRamp) = ramp;
    window(end - nRamp + 1:end) = flipud(ramp);
    source = source .* window;
end

function audio = render_binaural_source(source, hrirDirection)
    assert(size(hrirDirection, 1) == 2, "Expected two HRIR receiver channels.");
    left = conv(source, squeeze(hrirDirection(1, :)).', "full");
    right = conv(source, squeeze(hrirDirection(2, :)).', "full");
    audio = [left, right];
end

function varargout = normalise_group(varargin)
    cfg = varargin{end};
    signals = varargin(1:end - 1);
    maximum = 0;
    for iSignal = 1:numel(signals)
        maximum = max(maximum, max(abs(signals{iSignal}(:))));
    end
    scale = cfg.targetPeak / max(maximum, eps);
    varargout = cell(size(signals));
    for iSignal = 1:numel(signals)
        varargout{iSignal} = signals{iSignal} .* scale;
    end
end

function field = load_hrir_field(filePath)
    assert(isfile(filePath), "HRIR field not found: %s", filePath);
    loaded = load(filePath);
    if isfield(loaded, "field")
        field = loaded.field;
    else
        field.hrir = loaded.hrir;
        field.fs = loaded.fs;
        field.r = loaded.coordinatesCartesian;
    end
    assert(size(field.hrir, 2) == 2, ...
        "HRIR field must contain left and right receivers.");
    assert(isfield(field, "complexHrtf") && isfield(field, "fftLength"), ...
        "Continuous adaptive rendering requires exported complexHrtf and fftLength: %s", ...
        filePath);
end

function hrirBank = interpolate_hrir_directions(field, directions, cfg)

    switch cfg.renderInterpolation
        case {"SUpDEq_Bary_MCA_6dB", "SUpDEq_SH_MCA_6dB", ...
                "SUpDEq_NN_MCA_6dB", "OBTA_Bary_MCA_6dB", ...
                "OBTA_SH_MCA_6dB"}
            [ppMethod, ipMethod] = supdeq_renderer_methods( ...
                cfg.renderInterpolation);
            hrirBank = render_with_supdeq(field, directions, cfg, ...
                ppMethod, ipMethod);
        case "LocalComplexBary"
            hrirBank = zeros(size(directions, 1), 2, field.fftLength);
            for iDirection = 1:size(directions, 1)
                hrirBank(iDirection, :, :) = interpolate_hrir_direction( ...
                    field, directions(iDirection, :).', cfg);
            end
        case "LocalMinimumPhaseDelayIDW"
            hrirBank = zeros(size(directions, 1), 2, field.fftLength);
            for iDirection = 1:size(directions, 1)
                hrirBank(iDirection, :, :) = interpolate_minphase_delay_idw( ...
                    field, directions(iDirection, :).');
            end
        otherwise
            error("Unsupported adaptive render interpolation: %s", ...
                cfg.renderInterpolation);
    end

end

function hrirDirection = interpolate_minphase_delay_idw(field, direction)

    coordinates = field.r ./ vecnorm(field.r, 2, 2);
    direction = normalise(direction);
    [indices, weights] = local_idw_weights(coordinates, direction, 6, 2);
    complexHrtf = field.complexHrtf;
    logMagnitude = log(max(abs(complexHrtf(indices, :, :)), 1e-8));
    weightedLogMagnitude = squeeze(sum(logMagnitude .* ...
        reshape(weights(:), [], 1, 1), 1));
    magnitude = exp(weightedLogMagnitude);
    itdSeconds = estimate_itd_seconds(field.hrir, field.fs);
    itd = sum(itdSeconds(indices) .* weights(:));

    nFft = field.fftLength;
    nOneSided = nFft / 2 + 1;
    assert(size(magnitude, 1) == nOneSided, ...
        "Magnitude-delay renderer expected one-sided spectra matching fftLength.");
    frequency = linspace(0, field.fs / 2, nOneSided).';
    commonDelay = 64 / field.fs;
    spectrum = zeros(nOneSided, 2);
    for receiver = 1:2
        spectrum(:, receiver) = minimum_phase_spectrum_from_magnitude( ...
            magnitude(:, receiver), nFft);
    end
    spectrum(:, 1) = spectrum(:, 1) .* exp(-1i * 2 * pi * frequency .* ...
        (commonDelay - itd / 2));
    spectrum(:, 2) = spectrum(:, 2) .* exp(-1i * 2 * pi * frequency .* ...
        (commonDelay + itd / 2));
    spectrum(1, :) = real(spectrum(1, :));
    spectrum(end, :) = real(spectrum(end, :));
    twoSided = [spectrum; conj(spectrum(end - 1:-1:2, :))];
    hrirDirection = real(ifft(twoSided, nFft, 1)).';

end

function [indices, weights] = local_idw_weights(coordinates, direction, k, power)

    angularDistance = acos(max(-1, min(1, coordinates * normalise(direction))));
    [sortedDistance, order] = sort(angularDistance, "ascend");
    if sortedDistance(1) < 1e-10
        indices = order(1);
        weights = 1;
        return;
    end
    k = min(k, numel(order));
    indices = order(1:k);
    weights = 1 ./ max(sortedDistance(1:k), 1e-6) .^ power;
    weights = weights ./ sum(weights);

end

function itdSeconds = estimate_itd_seconds(hrir, fs)

    itdSeconds = zeros(size(hrir, 1), 1);
    for iDirection = 1:size(hrir, 1)
        left = squeeze(hrir(iDirection, 1, :));
        right = squeeze(hrir(iDirection, 2, :));
        correlation = conv(right, flipud(left), "full");
        [~, peak] = max(correlation);
        lag = peak - numel(left);
        itdSeconds(iDirection) = lag / fs;
    end

end

function spectrum = minimum_phase_spectrum_from_magnitude(magnitude, nFft)

    magnitude = max(magnitude(:), 1e-8);
    assert(numel(magnitude) == nFft / 2 + 1, ...
        "Minimum-phase reconstruction requires one-sided magnitude.");
    twoSidedLogMagnitude = [log(magnitude); log(magnitude(end - 1:-1:2))];
    cepstrum = real(ifft(twoSidedLogMagnitude));
    minimumPhaseCepstrum = zeros(size(cepstrum));
    minimumPhaseCepstrum(1) = cepstrum(1);
    minimumPhaseCepstrum(2:nFft / 2) = 2 * cepstrum(2:nFft / 2);
    minimumPhaseCepstrum(nFft / 2 + 1) = cepstrum(nFft / 2 + 1);
    fullSpectrum = exp(fft(minimumPhaseCepstrum));
    spectrum = fullSpectrum(1:nFft / 2 + 1);

end

function [ppMethod, ipMethod] = supdeq_renderer_methods(renderInterpolation)

    switch renderInterpolation
        case "SUpDEq_Bary_MCA_6dB"
            ppMethod = "SUpDEq";
            ipMethod = "Bary";
        case "SUpDEq_SH_MCA_6dB"
            ppMethod = "SUpDEq";
            ipMethod = "SH";
        case "SUpDEq_NN_MCA_6dB"
            ppMethod = "SUpDEq";
            ipMethod = "NN";
        case "OBTA_Bary_MCA_6dB"
            ppMethod = "OBTA";
            ipMethod = "Bary";
        case "OBTA_SH_MCA_6dB"
            ppMethod = "OBTA";
            ipMethod = "SH";
        otherwise
            error("Unsupported SUpDEq renderer: %s", renderInterpolation);
    end

end

function tf = uses_supdeq_renderer(renderInterpolation)

    tf = ismember(renderInterpolation, ["SUpDEq_Bary_MCA_6dB", ...
        "SUpDEq_SH_MCA_6dB", "SUpDEq_NN_MCA_6dB", ...
        "OBTA_Bary_MCA_6dB", "OBTA_SH_MCA_6dB"]);

end

function hrirBank = render_with_supdeq(field, directions, cfg, ppMethod, ipMethod)

    HRTFset = form_supdeq_input_for_rendering(field, cfg);
    interpolationGrid = to_supdeq_sampling_grid(cartesian_to_az_el(directions));
    clear AKerbErrorPersistent;
    [interpolatedSet, ~, ~] = supdeq_interpHRTF( ...
        HRTFset, interpolationGrid, ppMethod, ipMethod, ...
        cfg.supdeqMcDb, cfg.headRadius, cfg.supdeqTikhEps, ...
        cfg.supdeqLimitMC, cfg.supdeqMcKnee, cfg.supdeqMcMinPhase, ...
        char(cfg.supdeqLimFade));
    hrirBank = permute(cat(3, interpolatedSet.HRIR_L, ...
        interpolatedSet.HRIR_R), [2, 3, 1]);

end

function HRTFset = form_supdeq_input_for_rendering(field, cfg)

    nDirections = size(field.r, 1);
    maximumResolvableOrder = max(0, floor(sqrt(nDirections) - 1));
    fftLength = 2 * (size(field.complexHrtf, 2) - 1);
    assert(isscalar(fftLength) && isfinite(fftLength), ...
        "SUpDEq rendering requires a scalar FFT length.");

    HRTFset.HRTF_L = squeeze(field.complexHrtf(:, :, 1));
    HRTFset.HRTF_R = squeeze(field.complexHrtf(:, :, 2));
    if isfield(field, "freqHzWithDC") && ~isempty(field.freqHzWithDC)
        HRTFset.f = field.freqHzWithDC;
    else
        HRTFset.f = linspace(0, field.fs / 2, size(field.complexHrtf, 2));
    end
    HRTFset.fs = field.fs;
    HRTFset.FFToversize = 1;
    HRTFset.Nmax = min(cfg.supdeqMaxSHOrder, maximumResolvableOrder);
    HRTFset.samplingGrid = to_supdeq_sampling_grid(field.azElDeg);

end

function ensure_supdeq_renderer_paths(publicRoot)

    studyRoot = string(fileparts(fileparts(publicRoot)));
    dependencyRoot = fullfile(studyRoot, "dependencies");
    supdeqRoot = fullfile(dependencyRoot, "SUpDEq-master", "SUpDEq-master");
    paths = [ ...
        string(supdeqRoot), ...
        string(fullfile(supdeqRoot, "thirdParty", "AKtools")), ...
        string(fullfile(supdeqRoot, "thirdParty", "SOFiA R13_MIT-License", "SOFiA")), ...
        string(fullfile(supdeqRoot, "thirdParty", "sfs-matlab-2.5.0")), ...
        string(fullfile(supdeqRoot, "thirdParty", "TriangleRayIntersection"))];
    for iPath = 1:numel(paths)
        assert(isfolder(paths(iPath)), ...
            "Required SUpDEq rendering dependency folder not found: %s", ...
            paths(iPath));
    end
    addpath(char(paths(1)));
    for iPath = 2:numel(paths)
        addpath(genpath(char(paths(iPath))));
    end

end

function hrirDirection = interpolate_hrir_direction(field, direction, cfg)
    coordinates = field.r ./ vecnorm(field.r, 2, 2);
    direction = normalise(direction);
    angularDistance = acos(max(-1, min(1, coordinates * direction)));
    [sortedDistance, order] = sort(angularDistance, "ascend");

    if sortedDistance(1) < 1e-10
        complexSpectrum = squeeze(field.complexHrtf(order(1), :, :));
    else
        [vertices, weights] = spherical_barycentric_weights(coordinates, ...
            direction, cfg);
        complexSpectrum = squeeze(sum(field.complexHrtf(vertices, :, :) .* ...
            reshape(weights(:), [], 1, 1), 1));
    end

    nOneSided = size(complexSpectrum, 1);
    nFft = field.fftLength;
    assert(nOneSided == nFft / 2 + 1, ...
        "Continuous renderer expected one-sided spectra matching fftLength.");
    complexSpectrum(1, :) = real(complexSpectrum(1, :));
    complexSpectrum(end, :) = real(complexSpectrum(end, :));
    twoSided = [complexSpectrum; conj(complexSpectrum(end - 1:-1:2, :))];
    hrir = real(ifft(twoSided, nFft, 1));
    hrirDirection = hrir.';
end

function azElDeg = cartesian_to_az_el(r)

    r = r ./ vecnorm(r, 2, 2);
    [azimuth, elevation, ~] = cart2sph(r(:, 1), r(:, 2), r(:, 3));
    azElDeg = rad2deg([azimuth, elevation]);

end

function grid = to_supdeq_sampling_grid(azElDeg)

    azimuthDeg = mod(azElDeg(:, 1), 360);
    polarElevationDeg = 90 - azElDeg(:, 2);
    grid = [azimuthDeg, polarElevationDeg];

end

function rows = normalise_rows(rows)

    rows = rows ./ max(vecnorm(rows, 2, 2), eps);

end

function [vertices, weights] = spherical_barycentric_weights(coordinates, ...
        direction, cfg)

    persistent cachedCoordinates cachedTriangles
    if isempty(cachedCoordinates) || ~isequal(size(cachedCoordinates), size(coordinates)) || ...
            max(abs(cachedCoordinates - coordinates), [], "all") > 1e-12
        cachedCoordinates = coordinates;
        cachedTriangles = convhulln(coordinates);
    end

    direction = normalise(direction);
    bestError = inf;
    bestVertices = cachedTriangles(1, :);
    bestWeights = [1, 0, 0];
    for iTriangle = 1:size(cachedTriangles, 1)
        vertices = cachedTriangles(iTriangle, :);
        triangle = coordinates(vertices, :);
        weights = planar_barycentric_weights(triangle, direction);
        candidate = weights(1) * triangle(1, :) + weights(2) * triangle(2, :) + ...
            weights(3) * triangle(3, :);
        radialError = norm(normalise(candidate(:)) - direction(:));
        negativity = max(0, -min(weights));
        error = radialError + 10 * negativity;
        if error < bestError
            bestError = error;
            bestVertices = vertices;
            bestWeights = weights;
        end
        if all(weights >= -cfg.barycentricTolerance) && radialError < 1e-5
            bestVertices = vertices;
            bestWeights = weights;
            break;
        end
    end

    weights = max(bestWeights, 0);
    if sum(weights) <= eps
        [~, nearest] = max(coordinates * direction);
        vertices = nearest;
        weights = 1;
    else
        vertices = bestVertices;
        weights = weights ./ sum(weights);
    end
end

function weights = planar_barycentric_weights(triangle, direction)
    a = triangle(1, :).';
    b = triangle(2, :).';
    c = triangle(3, :).';
    n = cross(b - a, c - a);
    denom = dot(direction(:), n);
    if abs(denom) < 1e-12
        projected = direction(:);
    else
        projected = direction(:) * (dot(a, n) / denom);
    end
    weights = ([a, b, c; 1, 1, 1] \ [projected; 1]).';
end

function [tensor, coordinates] = load_metric_tensor(filePath)
    assert(isfile(filePath), "Metric tensor not found: %s", filePath);
    loaded = load(filePath, "metricTensor", "coordinatesCartesian", "tensorProvenance");
    assert(isfield(loaded, "metricTensor") && isfield(loaded, "coordinatesCartesian"), ...
        "Metric tensor file lacks required variables: %s", filePath);
    assert(isfield(loaded, "tensorProvenance") && ...
        string(loaded.tensorProvenance) == "fresh_behavioural_export_current_fisher_code", ...
        "Adaptive stimulus rendering requires a fresh behavioural-export tensor: %s", filePath);
    tensor = loaded.metricTensor;
    coordinates = loaded.coordinatesCartesian;
end

function assert_grid_agreement(first, second)
    assert(isequal(size(first), size(second)) && ...
        max(abs(first - second), [], "all") < 1e-9, ...
        "Stimulus HRIR and metric tensor coordinate grids do not agree.");
end

function metric = pair_metric_predictions(referenceTensor, fieldTensor, ...
        coordinates, rStandard, rTarget)
    rStandard = normalise(rStandard);
    rTarget = normalise(rTarget);
    midpoint = normalise(rStandard + rTarget);
    [~, evaluationIndex] = max(coordinates * midpoint);
    rEvaluation = normalise(coordinates(evaluationIndex, :).');
    basis = tangent_basis(rEvaluation);
    displacement = basis.' * (sphere_log_map(rEvaluation, rTarget) - ...
        sphere_log_map(rEvaluation, rStandard));
    reference = referenceTensor(:, :, evaluationIndex);
    field = fieldTensor(:, :, evaluationIndex);
    metric.predictedDPrimeReference = sqrt(max(displacement.' * reference * displacement, 0));
    metric.predictedDPrimeField = sqrt(max(displacement.' * field * displacement, 0));
    metric.localAIRM = airm_distance(reference + 1e-6 * eye(2), ...
        field + 1e-6 * eye(2));
end

function basis = tangent_basis(r)
    north = [0; 0; 1];
    if abs(dot(r, north)) > 0.95
        north = [0; 1; 0];
    end
    e1 = normalise(cross(north, r));
    e2 = normalise(cross(r, e1));
    basis = [e1, e2];
end

function v = sphere_log_map(base, target)
    cosine = max(-1, min(1, dot(base, target)));
    theta = acos(cosine);
    if theta < 1e-12
        v = zeros(3, 1);
    else
        v = theta * (target - cosine * base) / sin(theta);
    end
end

function target = sphere_exp_map(base, displacement)
    theta = norm(displacement);
    if theta < 1e-12
        target = base;
    else
        target = cos(theta) * base + sin(theta) * displacement / theta;
        target = normalise(target);
    end
end

function d = airm_distance(first, second)
    rootInv = sqrtm(inv(first));
    eigenvalues = eig(rootInv * second * rootInv);
    d = norm(log(max(real(eigenvalues), eps)));
end

function v = normalise(v)
    v = v ./ max(norm(v), eps);
end

function ensure_folder(folder)
    if ~isfolder(folder)
        mkdir(folder);
    end
end
