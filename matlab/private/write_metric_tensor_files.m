function write_metric_tensor_files(target, method, samplingCondition, fisher, cfg)
% Save the measured tensor once and one reconstruction tensor per test row.

    subjectFolder = fullfile(cfg.execution.tensorRoot, ...
        sprintf("subject_%04d", target.subjectId));
    ensure_results_folder(subjectFolder);

    if fisher.status == "completed"
        referencePath = fullfile(subjectFolder, "reference_metric_tensor.mat");
        if ~isfile(referencePath)
            subjectId = target.subjectId;
            sourceFile = target.filePath;
            coordinatesCartesian = target.r;
            coordinatesAzimuthElevationDeg = target.azElDeg;
            metricTensor = fisher.targetTensor;
            itdMode = fisher.targetITDMode;
            cueExtractionMode = fisher.cueExtractionMode;
            status = "completed";
            familyGram = fisher.targetFamilyGram;
            exportShOrders = fisher.exportShOrders;
            familyNames = fisher.familyNames;
            cueBandHz = fisher.cueBandHz;
            sigmaMon = cfg.sigmaMon; sigmaILD = cfg.sigmaILD;
            sigmaITD = cfg.sigmaITD; eta = cfg.eta;
            save(referencePath, "subjectId", "sourceFile", ...
                "coordinatesCartesian", "coordinatesAzimuthElevationDeg", ...
                "metricTensor", "itdMode", "cueExtractionMode", "status", ...
                "familyGram", "exportShOrders", "familyNames", "cueBandHz", ...
                "sigmaMon", "sigmaILD", "sigmaITD", "eta", "-v7.3");
        end
    end

    methodFileName = regexprep(char(method.name), "[^A-Za-z0-9_]", "_");
    reconstructionPath = fullfile(subjectFolder, sprintf( ...
        "%s_N%03d_metric_tensor.mat", methodFileName, ...
        samplingCondition.retentionCount));
    subjectId = target.subjectId;
    sourceFile = target.filePath;
    methodName = method.name;
    retainedDirections = samplingCondition.retentionCount;
    coordinatesCartesian = target.r;
    coordinatesAzimuthElevationDeg = target.azElDeg;
    metricTensor = fisher.reconstructedTensor;
    itdMode = fisher.reconstructedITDMode;
    cueExtractionMode = fisher.cueExtractionMode;
    status = fisher.status;
    message = fisher.message;
    crossFamilyGram = [];
    if isfield(fisher, "crossFamilyGram")
        crossFamilyGram = fisher.crossFamilyGram;
    end
    if isfield(fisher, "reconFamilyGram")
        familyGram = fisher.reconFamilyGram;
        exportShOrders = fisher.exportShOrders;
        airmByDirection = fisher.airmByDirection;
        nearFloorByDirection = fisher.nearFloorByDirection;
    else
        familyGram = [];
        exportShOrders = cfg.export.shOrders;
        airmByDirection = [];
        nearFloorByDirection = [];
    end
    cueBandHz = cfg.cueBand.limitHz;
    save(reconstructionPath, "subjectId", "sourceFile", "methodName", ...
        "retainedDirections", "coordinatesCartesian", ...
        "coordinatesAzimuthElevationDeg", "metricTensor", "itdMode", ...
        "cueExtractionMode", "status", "message", "familyGram", ...
        "crossFamilyGram", "exportShOrders", "airmByDirection", ...
        "nearFloorByDirection", "cueBandHz", "-v7.3");

end
