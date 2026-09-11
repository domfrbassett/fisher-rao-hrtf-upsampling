function plan = generate_lateral_median_head_condition_plan(studyRoot, cfg)
%GENERATE_LATERAL_MEDIAN_HEAD_CONDITION_PLAN Build the lateral-only test plan.

    arguments
        studyRoot (1, 1) string
        cfg.subjectId (1, 1) double = 33
        cfg.angularLevelsDeg (1, :) double = [30, 20, 15, 10, 7, 5, 3.5, 2.5, 1.75, 1.25, 0.9, 0.6]
        cfg.anchorAzimuthsDeg (1, :) double = [-45, 0, 45, 0]
        cfg.snapTargetsToGrid (1, 1) logical = false
        cfg.outputName (1, 1) string = "adaptive_condition_plan.csv"
        cfg.auditName (1, 1) string = "lateral_median_head_condition_plan_audit.csv"
    end

    fieldsRoot = fullfile(studyRoot, "fields");
    tensorsRoot = fullfile(fieldsRoot, "metric_tensors");
    matlabRoot = fullfile(studyRoot, "matlab");
    auditRoot = fullfile(studyRoot, "audit");
    if ~isfolder(auditRoot)
        mkdir(auditRoot);
    end

    referenceTensorPath = tensor_file(tensorsRoot, cfg.subjectId, "Measured", 793);
    loaded = load(referenceTensorPath, "coordinatesCartesian");
    coordinates = loaded.coordinatesCartesian;
    azElDeg = cartesian_to_az_el(coordinates);

    conditions = { ...
        {"Measured", 793, "reference"}, ...
        {"SUpDEq_MCA", 5, "reconstruction"}, ...
        {"SUpDEq_MCA", 19, "reconstruction"}, ...
        {"RANF", 5, "reconstruction"}, ...
        {"RANF", 19, "reconstruction"}, ...
        {"FSP_AE", 5, "reconstruction"}, ...
        {"FSP_AE", 19, "reconstruction"}};

    rows = repmat(empty_row(), 0, 1);
    for iAnchor = 1:numel(cfg.anchorAzimuthsDeg)
        anchor = choose_anchor(azElDeg, cfg.anchorAzimuthsDeg(iAnchor), 0);
        pairs = level_pairs("lateral", coordinates, azElDeg, anchor, ...
            cfg.angularLevelsDeg, cfg.snapTargetsToGrid);
        for iCondition = 1:numel(conditions)
            condition = conditions{iCondition};
            blockNumber = mod((iAnchor - 1) + (iCondition - 1), 4) + 1;
            rows = append_field_track(rows, cfg.subjectId, string(condition{1}), ...
                condition{2}, string(condition{3}), iAnchor, blockNumber, ...
                pairs, fieldsRoot, tensorsRoot);
        end
    end

    plan = struct2table(rows);
    outputPath = fullfile(matlabRoot, cfg.outputName);
    writetable(plan, outputPath);

    audit = make_condition_audit(plan);
    auditPath = fullfile(auditRoot, cfg.auditName);
    writetable(audit, auditPath);

    fprintf("Wrote lateral median-head condition plan with %d tracks and %d levels: %s\n", ...
        numel(unique(plan.trackId)), height(plan), outputPath);
    fprintf("Wrote lateral median-head condition audit: %s\n", auditPath);

end

function rows = append_field_track(rows, subjectId, method, retained, fieldType, ...
        anchorNumber, blockNumber, pairs, fieldsRoot, tensorsRoot)

    referenceTensorPath = tensor_file(tensorsRoot, subjectId, "Measured", 793);
    fieldTensorPath = tensor_file(tensorsRoot, subjectId, method, retained);
    metric = load(fieldTensorPath, "LSDdB", "ILDErrorDb");
    methodSafe = regexprep(char(method), "[^A-Za-z0-9_]", "_");
    trackId = sprintf("lateral_P%04d_%s_N%03d_anchor%02d", ...
        subjectId, methodSafe, retained, anchorNumber);

    for iLevel = 1:height(pairs)
        row = empty_row();
        row.trackId = trackId;
        row.blockId = sprintf("lateral_block_%02d", blockNumber);
        row.blockLabel = sprintf("Lateral judgement (%d/4)", blockNumber);
        row.blockType = "formal";
        row.axis = "lateral";
        row.question = "Which sound, A or B, sounded farther to the left?";
        row.virtualHrtfSubjectId = subjectId;
        row.fieldType = fieldType;
        row.method = method;
        row.retainedDirections = retained;
        row.fieldMat = hrir_file(fieldsRoot, subjectId, method, retained);
        row.referenceMetricTensorMat = referenceTensorPath;
        row.fieldMetricTensorMat = fieldTensorPath;
        row.anchorId = sprintf("lateral_anchor%02d", anchorNumber);
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

function audit = make_condition_audit(plan)

    trackIds = unique(plan.trackId, "stable");
    records = repmat(struct("trackId", "", "blockId", "", "subjectId", NaN, ...
        "method", "", "retainedDirections", NaN, "anchorId", "", ...
        "standardAzDeg", NaN, "standardElDeg", NaN, "levelCount", NaN, ...
        "minimumSeparationDeg", NaN, "maximumSeparationDeg", NaN), ...
        numel(trackIds), 1);
    for iTrack = 1:numel(trackIds)
        rows = plan(plan.trackId == trackIds(iTrack), :);
        records(iTrack).trackId = char(trackIds(iTrack));
        records(iTrack).blockId = char(rows.blockId(1));
        records(iTrack).subjectId = rows.virtualHrtfSubjectId(1);
        records(iTrack).method = char(rows.method(1));
        records(iTrack).retainedDirections = rows.retainedDirections(1);
        records(iTrack).anchorId = char(rows.anchorId(1));
        records(iTrack).standardAzDeg = rows.standardAzDeg(1);
        records(iTrack).standardElDeg = rows.standardElDeg(1);
        records(iTrack).levelCount = height(rows);
        records(iTrack).minimumSeparationDeg = min(rows.separationDeg);
        records(iTrack).maximumSeparationDeg = max(rows.separationDeg);
    end
    audit = struct2table(records);

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
            error("This condition plan is lateral-only.");
        end
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
    valid = angularSeparationDeg > 0 & vecnorm([targetX, targetY, targetZ] - ...
        [targetOppositeX, targetOppositeY, targetOppositeZ], 2, 2) > 1e-12;
    validRows = find(valid);
    roundedDirections = round([targetX(validRows), targetY(validRows), ...
        targetZ(validRows), targetOppositeX(validRows), ...
        targetOppositeY(validRows), targetOppositeZ(validRows)] * 1e10) / 1e10;
    [~, uniqueRows] = unique(roundedDirections, "rows", "stable");
    keep = validRows(uniqueRows);
    [~, order] = sort(angularSeparationDeg(keep), "descend");
    keep = keep(order);
    keep = keep(:);
    assert(numel(keep) >= 3, ...
        "Adaptive anchor %d produced fewer than three distinct nonzero levels.", ...
        anchor);
    pairs = table(standardIndex(keep), targetIndex(keep), ...
        targetOppositeIndex(keep), angularSeparationDeg(keep), ...
        standardAzDeg(keep), standardElDeg(keep), targetAzDeg(keep), ...
        targetElDeg(keep), targetOppositeAzDeg(keep), ...
        targetOppositeElDeg(keep), standardX(keep), standardY(keep), ...
        standardZ(keep), targetX(keep), targetY(keep), targetZ(keep), ...
        targetOppositeX(keep), targetOppositeY(keep), targetOppositeZ(keep), ...
        'VariableNames', {'standardIndex', 'targetIndex', ...
        'targetOppositeIndex', 'angularSeparationDeg', ...
        'standardAzDeg', 'standardElDeg', 'targetAzDeg', 'targetElDeg', ...
        'targetOppositeAzDeg', 'targetOppositeElDeg', 'standardX', ...
        'standardY', 'standardZ', 'targetX', 'targetY', 'targetZ', ...
        'targetOppositeX', 'targetOppositeY', 'targetOppositeZ'});

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
    if string(method) == "RANF"
        rawPath = string(fullfile(fieldsRoot, sprintf("subject_%04d", subjectId), ...
            sprintf("RANF_raw_N%03d_hrir_field.mat", retainedDirections)));
        assert(isfile(rawPath), ...
            "Missing raw RANF HRIR field for behavioural rendering: %s", rawPath);
        path = rawPath;
        return;
    end
    if string(method) == "FSP_AE"
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
    assert(isfile(path), "Missing metric tensor: %s", path);
end

function anchor = choose_anchor(azElDeg, targetAz, targetEl)
    score = abs(wrap_degrees(azElDeg(:, 1) - targetAz)) + ...
        1.5 * abs(azElDeg(:, 2) - targetEl);
    [~, anchor] = min(score);
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
