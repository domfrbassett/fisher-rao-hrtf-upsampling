function recon = load_external_comparator_reconstruction( ...
    sparseField, targetR, method, cfg)
% Load a generated comparator SOFA and map it onto the measured target grid.

    retentionCount = numel(sparseField.retainedIndices);
    [filePath, message] = resolve_external_comparator_sofa( ...
        sparseField.subjectId, retentionCount, method.name, cfg);

    if strlength(filePath) == 0
        recon = unavailable_reconstruction(sparseField, targetR, ...
            method.name, message);
        recon.barycentricFallbackCount = NaN;
        return;
    end

    external = read_sofa_hrtf_field(filePath, cfg);
    recon = resample_external_field_to_target_grid(external, targetR, cfg);
    recon.subjectId = sparseField.subjectId;
    recon.filePath = filePath;
    recon.methodName = method.name;
    recon.isAvailable = true;
    recon.message = "";
    recon.hasInterauralDelay = true;
    recon.itdProvenance = "external_comparator_sofa";
    recon.barycentricFallbackCount = NaN;
    recon = guard_finite_reconstruction(recon, sparseField, targetR, method);

end

function [filePath, message] = resolve_external_comparator_sofa( ...
    subjectId, retentionCount, methodName, cfg)
% Complete model-generated fields (no retained-node replacement), staged as
% <alignedRoot>/<METHOD>/N###/Sonicom_<id>.sofa.

    filePath = "";
    message = "";

    alignedPath = fullfile(string(cfg.externalComparators.alignedRoot), ...
        string(methodName), sprintf("N%03d", retentionCount), ...
        sprintf("Sonicom_%d.sofa", subjectId));
    if isfile(alignedPath)
        filePath = alignedPath;
    else
        message = sprintf("External comparator SOFA not found: %s", alignedPath);
    end

end

function recon = resample_external_field_to_target_grid(external, targetR, cfg)
% Map an external comparator SOFA onto the measured SONICOM target grid.
% Current exported comparator SOFAs should match the SONICOM grid up to
% numerical roundoff.
 
    nearest = nearest_direction_indices(external.r, targetR);
    angularErrorDeg = rad2deg(acos(max(min( ...
        sum(external.r(nearest, :) .* targetR, 2), 1), -1)));
    maxErrorDeg = max(angularErrorDeg);
 
    gridToleranceDeg = 1e-4;
    assert(maxErrorDeg <= gridToleranceDeg, ...
        "External SOFA directions do not match the target SONICOM grid. Max angular mismatch: %.6f deg.", ...
        maxErrorDeg);
 
    recon = external;
    recon.r = targetR;
    recon.azElDeg = cartesian_to_az_el(targetR);
    recon.hrir = external.hrir(nearest, :, :);
    recon = refresh_field_spectra(recon, cfg);
 
end

function nearest = nearest_direction_indices(sourceR, targetR)

    nearest = zeros(size(targetR, 1), 1);
    for iDirection = 1:size(targetR, 1)
        distances = sum((sourceR - targetR(iDirection, :)) .^ 2, 2);
        [~, nearest(iDirection)] = min(distances);
    end

end
