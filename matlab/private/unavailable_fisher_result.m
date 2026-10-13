function result = unavailable_fisher_result(nDirections, message, cfg)

    result.meanAIRM = NaN;
    result.medianAIRM = NaN;
    result.stdAIRM = NaN;
    result.iqrAIRM = NaN;
    result.airmByDirection = nan(nDirections, 1);
    result.meanDeterminantError = NaN;
    result.determinantErrorByDirection = nan(nDirections, 1);
    result.meanAnisotropyError = NaN;
    result.anisotropyErrorByDirection = nan(nDirections, 1);
    result.orientationErrorByDirection = nan(nDirections, 1);
    result.meanOrientationErrorRad = NaN;
    result.meanOrientationErrorDeg = NaN;
    result.orientationValidCount = NaN;
    result.orientationValidProportion = NaN;
    result.targetITDMode = "not_applicable";
    result.reconstructedITDMode = "not_applicable";
    result.cueExtractionMode = cfg.fisher.cueConvention;
    result.targetTensor = nan(2, 2, nDirections);
    result.reconstructedTensor = nan(2, 2, nDirections);
    result.targetPrincipalMAA = nan(nDirections, 2);
    result.reconstructedPrincipalMAA = nan(nDirections, 2);
    result.status = "not_applicable";
    result.message = message;

end
