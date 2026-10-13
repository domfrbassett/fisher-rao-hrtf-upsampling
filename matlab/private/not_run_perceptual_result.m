function result = not_run_perceptual_result(status, message)

    result.status = string(status);
    result.message = string(message);
    result.lateralBiasDeg = NaN;
    result.lateralRMSErrorDeg = NaN;
    result.polarBiasDeg = NaN;
    result.localPolarRMSErrorDeg = NaN;
    result.quadrantErrorPercent = NaN;
    result.polarGain = NaN;
    result.numExperiments = NaN;
    result.selfLateralRMSErrorDeg = NaN;
    result.selfLocalPolarRMSErrorDeg = NaN;
    result.selfQuadrantErrorPercent = NaN;
    result.selfPerceptualTrials = NaN;
    result.relativeLateralRMSErrorDeg = NaN;
    result.relativeLocalPolarRMSErrorDeg = NaN;
    result.relativeQuadrantErrorPercentagePoints = NaN;
    result.referenceConvention = "absolute_only";

end
