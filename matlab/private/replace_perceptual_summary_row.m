function summary = replace_perceptual_summary_row(summary, row, perceptual)
% Replace only observer-model outputs, preserving all completed objective
% and Fisher-tensor quantities in the existing evaluation row.

    summary.perceptualStatus(row) = perceptual.status;
    summary.lateralRMSErrorDeg(row) = perceptual.lateralRMSErrorDeg;
    summary.localPolarRMSErrorDeg(row) = perceptual.localPolarRMSErrorDeg;
    summary.quadrantErrorPercent(row) = perceptual.quadrantErrorPercent;
    summary.perceptualTrials(row) = perceptual.numExperiments;
    summary.selfLateralRMSErrorDeg(row) = ...
        perceptual.selfLateralRMSErrorDeg;
    summary.selfLocalPolarRMSErrorDeg(row) = ...
        perceptual.selfLocalPolarRMSErrorDeg;
    summary.selfQuadrantErrorPercent(row) = ...
        perceptual.selfQuadrantErrorPercent;
    summary.selfPerceptualTrials(row) = perceptual.selfPerceptualTrials;
    summary.relativeLateralRMSErrorDeg(row) = ...
        perceptual.relativeLateralRMSErrorDeg;
    summary.relativeLocalPolarRMSErrorDeg(row) = ...
        perceptual.relativeLocalPolarRMSErrorDeg;
    summary.relativeQuadrantErrorPercentagePoints(row) = ...
        perceptual.relativeQuadrantErrorPercentagePoints;
    summary.perceptualReferenceConvention(row) = ...
        perceptual.referenceConvention;

end
