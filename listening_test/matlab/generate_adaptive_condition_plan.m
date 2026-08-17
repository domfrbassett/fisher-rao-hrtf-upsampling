function plan = generate_adaptive_condition_plan(studyRoot, cfg)
%GENERATE_ADAPTIVE_CONDITION_PLAN Build compact staircase level table.
%
% The selected subjects are representative of the objective-evaluation cohort
% rather than chosen for behavioural convenience. The default method set keeps
% the study feasible while comparing the dense control with a classical
% interpolation method and two learning-based reconstructions.

    arguments
        studyRoot (1, 1) string
        cfg.virtualHrtfSubjectIds (1, :) double = [100, 80, 33, 104]
        cfg.methods (1, :) string = ["SUpDEq_MCA", "RANF", "FSP_AE"]
        cfg.retentionConditions (1, :) double = [19, 5]
        cfg.lateralAngularLevelsDeg (1, :) double = [30, 20, 15, 10, 5]
        cfg.polarAngularLevelsDeg (1, :) double = [30, 20, 15, 10, 5]
        cfg.lateralAnchorAzimuthsDeg (1, :) double = [-45, 0, 45]
        cfg.polarAnchorAzElDeg (:, 2) double = [-45, 0; 0, 0; 45, 0]
        cfg.compactBalancedDesign (1, 1) logical = true
        cfg.snapTargetsToGrid (1, 1) logical = true
        cfg.outputName (1, 1) string = "adaptive_condition_plan.csv"
    end

    fieldsRoot = fullfile(studyRoot, "fields");
    tensorsRoot = fullfile(fieldsRoot, "metric_tensors");
    matlabRoot = fullfile(studyRoot, "matlab");
    assert(isfolder(fieldsRoot) && isfolder(tensorsRoot), ...
        "Run behavioural HRIR/tensor export before creating the adaptive plan.");

    referenceTensorPath = tensor_file(tensorsRoot, cfg.virtualHrtfSubjectIds(1), ...
        "Measured", 793);
    loaded = load(referenceTensorPath, "coordinatesCartesian");
    coordinates = loaded.coordinatesCartesian;
    azElDeg = cartesian_to_az_el(coordinates);

    rows = repmat(empty_row(), 0, 1);
    if cfg.compactBalancedDesign
        rows = append_compact_balanced_tracks(rows, coordinates, azElDeg, cfg, ...
            fieldsRoot, tensorsRoot);
    else
        for subjectId = cfg.virtualHrtfSubjectIds
            for axis = ["lateral", "polar"]
                anchors = anchor_targets_for_axis(axis, cfg);
                levelsDeg = angular_levels_for_axis(axis, cfg);
                for anchorNumber = 1:size(anchors, 1)
                    anchor = choose_anchor(azElDeg, anchors(anchorNumber, 1), ...
                        anchors(anchorNumber, 2));
                    pairs = level_pairs(axis, coordinates, azElDeg, anchor, ...
                        levelsDeg, cfg.snapTargetsToGrid);
                    rows = append_field_tracks(rows, axis, subjectId, "Measured", 793, ...
                        "reference", anchorNumber, pairs, fieldsRoot, tensorsRoot);
                    for method = cfg.methods
                        for retained = cfg.retentionConditions
                            rows = append_field_tracks(rows, axis, subjectId, method, retained, ...
                                "reconstruction", anchorNumber, pairs, fieldsRoot, tensorsRoot);
                        end
                    end
                end
            end
        end
    end

    plan = struct2table(rows);
    outputPath = fullfile(matlabRoot, cfg.outputName);
    writetable(plan, outputPath);
    fprintf("Wrote adaptive condition plan with %d rendered levels: %s\n", ...
        height(plan), outputPath);

end

function rows = append_compact_balanced_tracks(rows, coordinates, azElDeg, cfg, ...
        fieldsRoot, tensorsRoot)

    lateralAnchors = [-45; 0; 45; 0];
    polarAnchors = [-45, 0; 0, 0; 45, 0; 0, 0];
    methodSchedule = [ ...
        "SUpDEq_MCA", "RANF", "FSP_AE"; ...
        "SUpDEq_MCA", "RANF", "FSP_AE"; ...
        "SUpDEq_MCA", "RANF", "FSP_AE"; ...
        "SUpDEq_MCA", "RANF", "FSP_AE"];
    retentionSchedule = [ ...
        19, 5, 5; ...
        5, 19, 5; ...
        5, 5, 19; ...
        19, 19, 19];

    for iSubject = 1:numel(cfg.virtualHrtfSubjectIds)
        subjectId = cfg.virtualHrtfSubjectIds(iSubject);
        scheduleRow = mod(iSubject - 1, size(methodSchedule, 1)) + 1;
        for axis = ["lateral", "polar"]
            levelsDeg = angular_levels_for_axis(axis, cfg);
            if axis == "lateral"
                anchorTarget = [lateralAnchors(scheduleRow), 0];
            else
                anchorTarget = polarAnchors(scheduleRow, :);
            end
            anchor = choose_anchor(azElDeg, anchorTarget(1), anchorTarget(2));
            pairs = level_pairs(axis, coordinates, azElDeg, anchor, ...
                levelsDeg, cfg.snapTargetsToGrid);
            rows = append_field_tracks(rows, axis, subjectId, "Measured", 793, ...
                "reference", scheduleRow, pairs, fieldsRoot, tensorsRoot);
            for iCondition = 1:size(methodSchedule, 2)
                method = methodSchedule(scheduleRow, iCondition);
                retained = retentionSchedule(scheduleRow, iCondition);
                rows = append_field_tracks(rows, axis, subjectId, method, retained, ...
                    "reconstruction", scheduleRow, pairs, fieldsRoot, tensorsRoot);
            end
        end
    end

end

function rows = append_field_tracks(rows, axis, subjectId, method, retained, ...
        fieldType, anchorNumber, pairs, fieldsRoot, tensorsRoot)

    referenceTensorPath = tensor_file(tensorsRoot, subjectId, "Measured", 793);
    fieldTensorPath = tensor_file(tensorsRoot, subjectId, method, retained);
    metric = load(fieldTensorPath, "LSDdB", "ILDErrorDb", "tensorProvenance");
    assert(string(metric.tensorProvenance) == ...
        "fresh_behavioural_export_current_fisher_code", ...
        "Adaptive condition refers to an obsolete metric tensor.");
    methodSafe = regexprep(char(method), "[^A-Za-z0-9_]", "_");
    trackId = sprintf("%s_P%04d_%s_N%03d_anchor%02d", ...
        char(axis), subjectId, methodSafe, retained, anchorNumber);

    for iLevel = 1:height(pairs)
        row = empty_row();
        row.trackId = trackId;
        row.blockId = sprintf("adaptive_%s", char(axis));
        row.blockLabel = sprintf("Adaptive %s judgement", char(axis));
        row.blockType = "formal";
        row.axis = axis;
        if axis == "lateral"
            row.question = "Which sound, A or B, sounded farther to the left?";
        else
            row.question = "Which sound, A or B, sounded higher up?";
        end
        row.virtualHrtfSubjectId = subjectId;
        row.fieldType = fieldType;
        row.method = method;
        row.retainedDirections = retained;
        row.fieldMat = hrir_file(fieldsRoot, subjectId, method, retained);
        row.referenceMetricTensorMat = referenceTensorPath;
        row.fieldMetricTensorMat = fieldTensorPath;
        row.anchorId = sprintf("%s_anchor%02d", char(axis), anchorNumber);
        row.levelIndex = iLevel;
        row.separationDeg = pairs.angularSeparationDeg(iLevel);
        row.standardIndex = pairs.standardIndex(iLevel);
        row.targetIndex = pairs.targetIndex(iLevel);
        row.targetOppositeIndex = pairs.targetOppositeIndex(iLevel);
        row.standardAzDeg = pairs.standardAzDeg(iLevel);
        row.standardElDeg = pairs.standardElDeg(iLevel);
        row.targetAzDeg = pairs.targetAzDeg(iLevel);
        row.targetElDeg = pairs.targetElDeg(iLevel);
        row.targetOppositeAzDeg = pairs.targetOppositeAzDeg(iLevel);
        row.targetOppositeElDeg = pairs.targetOppositeElDeg(iLevel);
        row.standardX = pairs.standardX(iLevel);
        row.standardY = pairs.standardY(iLevel);
        row.standardZ = pairs.standardZ(iLevel);
        row.targetX = pairs.targetX(iLevel);
        row.targetY = pairs.targetY(iLevel);
        row.targetZ = pairs.targetZ(iLevel);
        row.targetOppositeX = pairs.targetOppositeX(iLevel);
        row.targetOppositeY = pairs.targetOppositeY(iLevel);
        row.targetOppositeZ = pairs.targetOppositeZ(iLevel);
        row.LSDdB = metric.LSDdB;
        row.ILDErrorDb = metric.ILDErrorDb;
        rows(end + 1, 1) = row; %#ok<AGROW>
    end

end

function levelsDeg = angular_levels_for_axis(axis, cfg)
    if axis == "lateral"
        levelsDeg = cfg.lateralAngularLevelsDeg;
    else
        levelsDeg = cfg.polarAngularLevelsDeg;
    end
end

function anchors = anchor_targets_for_axis(axis, cfg)
    if axis == "lateral"
        anchors = [cfg.lateralAnchorAzimuthsDeg(:), ...
            zeros(numel(cfg.lateralAnchorAzimuthsDeg), 1)];
    else
        anchors = cfg.polarAnchorAzElDeg;
    end
end

function anchor = choose_anchor(azElDeg, targetAz, targetEl)
    score = abs(wrap_degrees(azElDeg(:, 1) - targetAz)) + ...
        1.5 * abs(azElDeg(:, 2) - targetEl);
    [~, anchor] = min(score);
end

function pairs = level_pairs(axis, coordinates, azElDeg, anchor, levelsDeg, ...
        snapTargetsToGrid)
    standardIndex = zeros(numel(levelsDeg), 1);
    targetIndex = zeros(numel(levelsDeg), 1);
    targetOppositeIndex = zeros(numel(levelsDeg), 1);
    angularSeparationDeg = zeros(numel(levelsDeg), 1);
    standardAzDeg = zeros(numel(levelsDeg), 1);
    standardElDeg = zeros(numel(levelsDeg), 1);
    targetAzDeg = zeros(numel(levelsDeg), 1);
    targetElDeg = zeros(numel(levelsDeg), 1);
    targetOppositeAzDeg = zeros(numel(levelsDeg), 1);
    targetOppositeElDeg = zeros(numel(levelsDeg), 1);
    standardX = zeros(numel(levelsDeg), 1);
    standardY = zeros(numel(levelsDeg), 1);
    standardZ = zeros(numel(levelsDeg), 1);
    targetX = zeros(numel(levelsDeg), 1);
    targetY = zeros(numel(levelsDeg), 1);
    targetZ = zeros(numel(levelsDeg), 1);
    targetOppositeX = zeros(numel(levelsDeg), 1);
    targetOppositeY = zeros(numel(levelsDeg), 1);
    targetOppositeZ = zeros(numel(levelsDeg), 1);
    anchorAz = azElDeg(anchor, 1);
    anchorEl = azElDeg(anchor, 2);
    standardVector = normalise_row(coordinates(anchor, :));
    for iLevel = 1:numel(levelsDeg)
        if axis == "lateral"
            targetAz = anchorAz + levelsDeg(iLevel);
            targetEl = anchorEl;
            targetOppositeAz = anchorAz - levelsDeg(iLevel);
            targetOppositeEl = anchorEl;
        else
            targetAz = anchorAz;
            targetEl = anchorEl + levelsDeg(iLevel);
            targetOppositeAz = anchorAz;
            targetOppositeEl = anchorEl - levelsDeg(iLevel);
        end
        targetEl = max(-89, min(89, targetEl));
        targetOppositeEl = max(-89, min(89, targetOppositeEl));
        requestedTargetVector = sph2cart_unit(targetAz, targetEl);
        requestedTargetOppositeVector = sph2cart_unit(targetOppositeAz, ...
            targetOppositeEl);
        [~, target] = max(coordinates * requestedTargetVector.');
        [~, targetOpposite] = max(coordinates * requestedTargetOppositeVector.');
        if snapTargetsToGrid
            targetVector = normalise_row(coordinates(target, :));
            targetOppositeVector = normalise_row(coordinates(targetOpposite, :));
            storedTargetAz = azElDeg(target, 1);
            storedTargetEl = azElDeg(target, 2);
            storedTargetOppositeAz = azElDeg(targetOpposite, 1);
            storedTargetOppositeEl = azElDeg(targetOpposite, 2);
        else
            targetVector = normalise_row(requestedTargetVector);
            targetOppositeVector = normalise_row(requestedTargetOppositeVector);
            storedTargetAz = targetAz;
            storedTargetEl = targetEl;
            storedTargetOppositeAz = targetOppositeAz;
            storedTargetOppositeEl = targetOppositeEl;
        end
        standardIndex(iLevel) = anchor;
        targetIndex(iLevel) = target;
        targetOppositeIndex(iLevel) = targetOpposite;
        angularSeparationDeg(iLevel) = acosd(max(-1, min(1, ...
            standardVector * targetVector.')));
        standardAzDeg(iLevel) = anchorAz;
        standardElDeg(iLevel) = anchorEl;
        targetAzDeg(iLevel) = storedTargetAz;
        targetElDeg(iLevel) = storedTargetEl;
        targetOppositeAzDeg(iLevel) = storedTargetOppositeAz;
        targetOppositeElDeg(iLevel) = storedTargetOppositeEl;
        standardX(iLevel) = standardVector(1);
        standardY(iLevel) = standardVector(2);
        standardZ(iLevel) = standardVector(3);
        targetX(iLevel) = targetVector(1);
        targetY(iLevel) = targetVector(2);
        targetZ(iLevel) = targetVector(3);
        targetOppositeX(iLevel) = targetOppositeVector(1);
        targetOppositeY(iLevel) = targetOppositeVector(2);
        targetOppositeZ(iLevel) = targetOppositeVector(3);
    end
    if snapTargetsToGrid
        valid = angularSeparationDeg > 0 & targetIndex ~= anchor & ...
            targetOppositeIndex ~= anchor & targetIndex ~= targetOppositeIndex;
    else
        valid = angularSeparationDeg > 0 & vecnorm([targetX, targetY, targetZ] - ...
            [targetOppositeX, targetOppositeY, targetOppositeZ], 2, 2) > 1e-12;
    end
    validRows = find(valid);
    if snapTargetsToGrid
        [~, uniqueRows] = unique([targetIndex(validRows), ...
            targetOppositeIndex(validRows)], "rows", "stable");
        keep = validRows(uniqueRows);
    else
        roundedDirections = round([targetX(validRows), targetY(validRows), ...
            targetZ(validRows), targetOppositeX(validRows), ...
            targetOppositeY(validRows), targetOppositeZ(validRows)] * 1e10) / 1e10;
        [~, uniqueRows] = unique(roundedDirections, "rows", "stable");
        keep = validRows(uniqueRows);
    end
    [~, order] = sort(angularSeparationDeg(keep), "descend");
    keep = keep(order);
    assert(numel(keep) >= 3, ...
        "Adaptive anchor %d on %s axis produced fewer than three distinct nonzero levels.", ...
        anchor, axis);
    standardIndex = standardIndex(keep);
    targetIndex = targetIndex(keep);
    targetOppositeIndex = targetOppositeIndex(keep);
    angularSeparationDeg = angularSeparationDeg(keep);
    standardAzDeg = standardAzDeg(keep);
    standardElDeg = standardElDeg(keep);
    targetAzDeg = targetAzDeg(keep);
    targetElDeg = targetElDeg(keep);
    targetOppositeAzDeg = targetOppositeAzDeg(keep);
    targetOppositeElDeg = targetOppositeElDeg(keep);
    standardX = standardX(keep);
    standardY = standardY(keep);
    standardZ = standardZ(keep);
    targetX = targetX(keep);
    targetY = targetY(keep);
    targetZ = targetZ(keep);
    targetOppositeX = targetOppositeX(keep);
    targetOppositeY = targetOppositeY(keep);
    targetOppositeZ = targetOppositeZ(keep);
    pairs = table(standardIndex, targetIndex, targetOppositeIndex, ...
        angularSeparationDeg, standardAzDeg, standardElDeg, targetAzDeg, ...
        targetElDeg, targetOppositeAzDeg, targetOppositeElDeg, ...
        standardX, standardY, standardZ, targetX, targetY, targetZ, ...
        targetOppositeX, targetOppositeY, targetOppositeZ);
end

function row = empty_row()
    row = struct("trackId", "", "blockId", "", "blockLabel", "", ...
        "blockType", "", "axis", "", "question", "", ...
        "virtualHrtfSubjectId", NaN, "fieldType", "", "method", "", ...
        "retainedDirections", NaN, "fieldMat", "", ...
        "referenceMetricTensorMat", "", "fieldMetricTensorMat", "", ...
        "anchorId", "", "levelIndex", NaN, "separationDeg", NaN, ...
        "standardIndex", NaN, "targetIndex", NaN, ...
        "targetOppositeIndex", NaN, ...
        "standardAzDeg", NaN, "standardElDeg", NaN, ...
        "targetAzDeg", NaN, "targetElDeg", NaN, ...
        "targetOppositeAzDeg", NaN, "targetOppositeElDeg", NaN, ...
        "standardX", NaN, "standardY", NaN, "standardZ", NaN, ...
        "targetX", NaN, "targetY", NaN, "targetZ", NaN, ...
        "targetOppositeX", NaN, "targetOppositeY", NaN, ...
        "targetOppositeZ", NaN, ...
        "LSDdB", NaN, "ILDErrorDb", NaN);
end

function path = hrir_file(fieldsRoot, subjectId, method, retainedDirections)
    fileMethod = regexprep(char(method), "[^A-Za-z0-9_]", "_");
    if string(method) == "RANF" && ...
            string(getenv("FISHERRAO_USE_RANF_RAW_FOR_RENDERING")) == "true"
        rawPath = string(fullfile(fieldsRoot, sprintf("subject_%04d", subjectId), ...
            sprintf("RANF_raw_N%03d_hrir_field.mat", retainedDirections)));
        assert(isfile(rawPath), ...
            "Missing raw RANF HRIR field for behavioural rendering: %s", rawPath);
        path = rawPath;
        return;
    end
    if string(method) == "FSP_AE" && ...
            string(getenv("FISHERRAO_USE_FSP_AE_RAW_FOR_RENDERING")) == "true"
        rawPath = string(fullfile(fieldsRoot, sprintf("subject_%04d", subjectId), ...
            sprintf("FSP_AE_raw_N%03d_hrir_field.mat", retainedDirections)));
        assert(isfile(rawPath), ...
            "Missing raw FSP-AE HRIR field for behavioural rendering: %s", rawPath);
        path = rawPath;
        return;
    end
    path = string(fullfile(fieldsRoot, sprintf("subject_%04d", subjectId), ...
        sprintf("%s_N%03d_hrir_field.mat", fileMethod, retainedDirections)));
    assert(isfile(path), "Missing exported HRIR field: %s", path);
end

function path = tensor_file(tensorsRoot, subjectId, method, retainedDirections)
    fileMethod = regexprep(char(method), "[^A-Za-z0-9_]", "_");
    path = string(fullfile(tensorsRoot, sprintf("subject_%04d", subjectId), ...
        sprintf("%s_N%03d_metric_tensor.mat", fileMethod, retainedDirections)));
    assert(isfile(path), "Missing fresh behavioural metric tensor: %s", path);
end

function azElDeg = cartesian_to_az_el(r)
    r = r ./ vecnorm(r, 2, 2);
    [azimuth, elevation, ~] = cart2sph(r(:, 1), r(:, 2), r(:, 3));
    azElDeg = rad2deg([azimuth, elevation]);
end

function r = sph2cart_unit(azDeg, elDeg)
    az = deg2rad(azDeg);
    el = deg2rad(elDeg);
    r = [cos(el) * cos(az), cos(el) * sin(az), sin(el)];
end

function r = normalise_row(r)
    r = r ./ max(norm(r), eps);
end

function degrees = wrap_degrees(degrees)
    degrees = mod(degrees + 180, 360) - 180;
end
