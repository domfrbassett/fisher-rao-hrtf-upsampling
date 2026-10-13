function summary = build_airm_summary_table(dataset, evaluationIndices, ...
        upsamplers, sampling, reconstructions, signalResults, fisherResults, ...
        perceptualResults)

    nRows = numel(evaluationIndices) * numel(sampling) * numel(upsamplers);
    subjectId = zeros(nRows, 1);
    method = strings(nRows, 1);
    retainedDirections = zeros(nRows, 1);
    barycentricFallbackCount = nan(nRows, 1);
    status = strings(nRows, 1);
    message = strings(nRows, 1);
    meanAIRM = zeros(nRows, 1);
    medianAIRM = zeros(nRows, 1);
    stdAIRM = zeros(nRows, 1);
    iqrAIRM = zeros(nRows, 1);
    meanDeterminantError = zeros(nRows, 1);
    meanAnisotropyError = zeros(nRows, 1);
    meanOrientationErrorDeg = zeros(nRows, 1);
    orientationValidCount = zeros(nRows, 1);
    orientationValidProportion = zeros(nRows, 1);
    targetITDMode = strings(nRows, 1);
    reconstructedITDMode = strings(nRows, 1);
    cueExtractionMode = strings(nRows, 1);
    LSDdB = zeros(nRows, 1);
    ILDErrorDb = zeros(nRows, 1);
    LSDdB_16k = nan(nRows, 1);
    ILDErrorDb_16k = nan(nRows, 1);
    nonFiniteDirections = zeros(nRows, 1);
    nearFloorProportion = nan(nRows, 1);
    cueBandHz = nan(nRows, 1);
    perceptualStatus = strings(nRows, 1);
    lateralRMSErrorDeg = nan(nRows, 1);
    localPolarRMSErrorDeg = nan(nRows, 1);
    quadrantErrorPercent = nan(nRows, 1);
    perceptualTrials = nan(nRows, 1);
    selfLateralRMSErrorDeg = nan(nRows, 1);
    selfLocalPolarRMSErrorDeg = nan(nRows, 1);
    selfQuadrantErrorPercent = nan(nRows, 1);
    selfPerceptualTrials = nan(nRows, 1);
    relativeLateralRMSErrorDeg = nan(nRows, 1);
    relativeLocalPolarRMSErrorDeg = nan(nRows, 1);
    relativeQuadrantErrorPercentagePoints = nan(nRows, 1);
    perceptualReferenceConvention = strings(nRows, 1);

    row = 0;

    for iSub = 1:numel(evaluationIndices)
        for iCond = 1:numel(sampling)
            for iMethod = 1:numel(upsamplers)

                row = row + 1;
                fisher = fisherResults(iSub, iCond, iMethod);
                signal = signalResults(iSub, iCond, iMethod);
                recon = reconstructions{iSub, iCond, iMethod};
                perceptual = perceptualResults(iSub, iCond, iMethod);

                subjectId(row) = dataset(evaluationIndices(iSub)).subjectId;
                method(row) = upsamplers(iMethod).name;
                retainedDirections(row) = sampling(iCond).retentionCount;
                if isfield(recon, "barycentricFallbackCount")
                    barycentricFallbackCount(row) = recon.barycentricFallbackCount;
                end
                status(row) = fisher.status;
                message(row) = recon.message;
                if strlength(fisher.message) > 0
                    message(row) = fisher.message;
                end
                meanAIRM(row) = fisher.meanAIRM;
                medianAIRM(row) = fisher.medianAIRM;
                stdAIRM(row) = fisher.stdAIRM;
                iqrAIRM(row) = fisher.iqrAIRM;
                meanDeterminantError(row) = fisher.meanDeterminantError;
                meanAnisotropyError(row) = fisher.meanAnisotropyError;
                meanOrientationErrorDeg(row) = fisher.meanOrientationErrorDeg;
                orientationValidCount(row) = fisher.orientationValidCount;
                orientationValidProportion(row) = fisher.orientationValidProportion;
                targetITDMode(row) = fisher.targetITDMode;
                reconstructedITDMode(row) = fisher.reconstructedITDMode;
                cueExtractionMode(row) = fisher.cueExtractionMode;
                LSDdB(row) = signal.LSD;
                ILDErrorDb(row) = signal.ILD;
                if isfield(signal, "LSD16k")
                    LSDdB_16k(row) = signal.LSD16k;
                    ILDErrorDb_16k(row) = signal.ILD16k;
                end
                if isfield(recon, "nonFiniteDirections")
                    nonFiniteDirections(row) = recon.nonFiniteDirections;
                end
                if isfield(fisher, "nearFloorProportion")
                    nearFloorProportion(row) = fisher.nearFloorProportion;
                end
                if isfield(fisher, "cueBandHz")
                    cueBandHz(row) = fisher.cueBandHz;
                end
                perceptualStatus(row) = perceptual.status;
                lateralRMSErrorDeg(row) = perceptual.lateralRMSErrorDeg;
                localPolarRMSErrorDeg(row) = perceptual.localPolarRMSErrorDeg;
                quadrantErrorPercent(row) = perceptual.quadrantErrorPercent;
                perceptualTrials(row) = perceptual.numExperiments;
                selfLateralRMSErrorDeg(row) = perceptual.selfLateralRMSErrorDeg;
                selfLocalPolarRMSErrorDeg(row) = ...
                    perceptual.selfLocalPolarRMSErrorDeg;
                selfQuadrantErrorPercent(row) = perceptual.selfQuadrantErrorPercent;
                selfPerceptualTrials(row) = perceptual.selfPerceptualTrials;
                relativeLateralRMSErrorDeg(row) = ...
                    perceptual.relativeLateralRMSErrorDeg;
                relativeLocalPolarRMSErrorDeg(row) = ...
                    perceptual.relativeLocalPolarRMSErrorDeg;
                relativeQuadrantErrorPercentagePoints(row) = ...
                    perceptual.relativeQuadrantErrorPercentagePoints;
                perceptualReferenceConvention(row) = perceptual.referenceConvention;

            end
        end
    end

    summary = table(subjectId, method, retainedDirections, ...
        barycentricFallbackCount, status, message, meanAIRM, medianAIRM, ...
        stdAIRM, iqrAIRM, meanDeterminantError, meanAnisotropyError, ...
        meanOrientationErrorDeg, orientationValidCount, ...
        orientationValidProportion, targetITDMode, reconstructedITDMode, ...
        cueExtractionMode, LSDdB, ILDErrorDb, LSDdB_16k, ILDErrorDb_16k, ...
        nonFiniteDirections, nearFloorProportion, cueBandHz, ...
        perceptualStatus, lateralRMSErrorDeg, ...
        localPolarRMSErrorDeg, quadrantErrorPercent, perceptualTrials, ...
        selfLateralRMSErrorDeg, selfLocalPolarRMSErrorDeg, ...
        selfQuadrantErrorPercent, selfPerceptualTrials, ...
        relativeLateralRMSErrorDeg, relativeLocalPolarRMSErrorDeg, ...
        relativeQuadrantErrorPercentagePoints, perceptualReferenceConvention);

end
