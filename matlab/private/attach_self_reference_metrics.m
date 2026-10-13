function result = attach_self_reference_metrics(result, selfReference, cfg)
% Store absolute metrics and their signed degradation relative to dense self.

    if ~cfg.perceptual.reportRelativeToSelf || selfReference.status ~= "completed"
        return;
    end

    result.selfLateralRMSErrorDeg = selfReference.lateralRMSErrorDeg;
    result.selfLocalPolarRMSErrorDeg = selfReference.localPolarRMSErrorDeg;
    result.selfQuadrantErrorPercent = selfReference.quadrantErrorPercent;
    result.selfPerceptualTrials = selfReference.numExperiments;
    result.referenceConvention = "absolute_and_relative_to_dense_self";

    if result.status == "completed"
        result.relativeLateralRMSErrorDeg = result.lateralRMSErrorDeg - ...
            selfReference.lateralRMSErrorDeg;
        result.relativeLocalPolarRMSErrorDeg = result.localPolarRMSErrorDeg - ...
            selfReference.localPolarRMSErrorDeg;
        result.relativeQuadrantErrorPercentagePoints = ...
            result.quadrantErrorPercent - selfReference.quadrantErrorPercent;
    end

end
