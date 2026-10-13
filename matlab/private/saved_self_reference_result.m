function [result, isAvailable] = saved_self_reference_result(summary, subjectId, cfg)
% Recover a self-reference already propagated into a resumed summary table.

    result = not_run_perceptual_result("not_run", ...
        "Dense self-reference has not yet been evaluated.");
    isAvailable = false;
    if isempty(summary) || ~ismember("selfLateralRMSErrorDeg", ...
            string(summary.Properties.VariableNames))
        return;
    end

    idx = summary.subjectId == subjectId & ...
        ~isnan(summary.selfLateralRMSErrorDeg) & ...
        ~isnan(summary.selfLocalPolarRMSErrorDeg) & ...
        ~isnan(summary.selfQuadrantErrorPercent);
    if ismember("selfPerceptualTrials", string(summary.Properties.VariableNames))
        idx = idx & summary.selfPerceptualTrials == cfg.perceptual.numExperiments;
    end
    first = find(idx, 1, "first");
    if isempty(first)
        return;
    end

    result.status = "completed";
    result.message = "";
    result.lateralRMSErrorDeg = summary.selfLateralRMSErrorDeg(first);
    result.localPolarRMSErrorDeg = summary.selfLocalPolarRMSErrorDeg(first);
    result.quadrantErrorPercent = summary.selfQuadrantErrorPercent(first);
    result.numExperiments = cfg.perceptual.numExperiments;
    isAvailable = true;

end
