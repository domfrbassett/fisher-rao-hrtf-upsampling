function recon = reconstruct_hrtf_field(sparseField, targetR, method, cfg)
% Call the official SUpDEq interpolation entry point, then return data in
% the internal direction-major convention.

    if method.preprocessing == "ExternalSOFA"
        recon = load_external_comparator_reconstruction( ...
            sparseField, targetR, method, cfg);
        return;
    end

    if method.interpolation == "Bary" && size(sparseField.r, 1) < 4
        recon = unavailable_reconstruction(sparseField, targetR, method.name, ...
            "Not applicable: three directions cannot define the closed hull required by SUpDEq Bary.");
        recon.barycentricFallbackCount = NaN;
        return;
    end
    if method.interpolation == "Bary" && ~hull_encloses_origin(sparseField.r)
        recon = unavailable_reconstruction(sparseField, targetR, method.name, ...
            "Not applicable: the retained directions do not form a closed " + ...
            "hull around the listener, so barycentric weights are undefined " + ...
            "for some target directions.");
        recon.barycentricFallbackCount = NaN;
        return;
    end

    assert(exist("supdeq_interpHRTF", "file") == 2, ...
        "supdeq_interpHRTF was not found. Set cfg.toolbox.supdeqRoot.");

    HRTFset = form_supdeq_input(sparseField, cfg);
    targetAzElDeg = cartesian_to_az_el(targetR);
    appliedInterpolation = method.interpolation;
    interpolationGrid = to_supdeq_sampling_grid( ...
        cartesian_to_az_el(targetR));

    if ~isnan(method.magnitudeCorrectionDb)
        clear AKerbErrorPersistent;
    end

    try
        [interpolatedSet, HRTFLeft, HRTFRight] = supdeq_interpHRTF( ...
            HRTFset, interpolationGrid, char(method.preprocessing), ...
            char(appliedInterpolation), method.magnitudeCorrectionDb, ...
            cfg.headRadius, cfg.supdeq.tikhEps, cfg.supdeq.limitMC, ...
            cfg.supdeq.mcKnee, cfg.supdeq.mcMinPhase, ...
            char(cfg.supdeq.limFade));
    catch exception
        retryError = exception;
        interpolatedSet = [];
        if ~isnan(method.magnitudeCorrectionDb)
            clear AKerbErrorPersistent;
            try
                [interpolatedSet, HRTFLeft, HRTFRight] = supdeq_interpHRTF( ...
                    HRTFset, interpolationGrid, char(method.preprocessing), ...
                    char(appliedInterpolation), method.magnitudeCorrectionDb, ...
                    cfg.headRadius, cfg.supdeq.tikhEps, cfg.supdeq.limitMC, ...
                    cfg.supdeq.mcKnee, cfg.supdeq.mcMinPhase, ...
                    char(cfg.supdeq.limFade));
            catch retryException
                retryError = retryException;
            end
        end
        if isempty(interpolatedSet)
            % Record the SUpDEq failure for this condition instead of
            % aborting the study. At very sparse grids the natural-neighbour
            % (Voronoi) weights are undefined and the interpolated fields
            % contain NaN, which SUpDEq's magnitude-correction stage then
            % rejects.
            recon = unavailable_reconstruction(sparseField, targetR, ...
                method.name, "Not applicable: SUpDEq " + ...
                string(method.interpolation) + " interpolation failed (" + ...
                string(retryError.identifier) + ": " + ...
                string(retryError.message) + ").");
            recon.barycentricFallbackCount = NaN;
            recon.nonFiniteDirections = NaN;
            return;
        end
    end

    supdeqComplexHrtf = normalise_supdeq_output(HRTFLeft, HRTFRight, ...
        size(targetR, 1), cfg.nFreqBins + 1);

    recon = sparseField;
    recon.r = targetR;
    recon.azElDeg = targetAzElDeg;
    recon.hrir = permute(cat(3, interpolatedSet.HRIR_L, ...
        interpolatedSet.HRIR_R), [2, 3, 1]);
    recon = refresh_field_spectra(recon, cfg);
    % Real HRIRs cannot retain imaginary DC/Nyquist components sometimes
    % returned by SUpDEq. Require every physically meaningful interior bin
    % to remain exact, and evaluate the playable real-valued reconstruction.
    spectralDifference = recon.complexHrtf(:, 2:end-1, :) - ...
        supdeqComplexHrtf(:, 2:end-1, :);
    interiorRelativeError = norm(spectralDifference(:)) / ...
        max(norm(reshape(supdeqComplexHrtf(:, 2:end-1, :), [], 1)), eps);
    recon.supdeqInteriorRelativeError = interiorRelativeError;
    recon.hasInterauralDelay = true;
    recon.itdProvenance = "complex_hrtf_reconstruction";
    recon.methodName = method.name;
    recon.isAvailable = true;
    recon.message = "";
    if method.interpolation == "Bary"
        if isfield(interpolatedSet, "barycentricFallbackCount")
            recon.barycentricFallbackCount = ...
                double(interpolatedSet.barycentricFallbackCount);
        else
            recon.barycentricFallbackCount = 0;
        end
    end
    recon = guard_finite_reconstruction(recon, sparseField, targetR, method);

end

function inside = hull_encloses_origin(r)
% True if the convex hull of the unit vectors r strictly contains the
% origin, i.e. every ray from the listener intersects a hull triangle.

    K = convhull(r(:, 1), r(:, 2), r(:, 3));
    centroid = mean(r, 1);
    inside = true;
    for k = 1:size(K, 1)
        A = r(K(k, 1), :); B = r(K(k, 2), :); C = r(K(k, 3), :);
        n = cross(B - A, C - A);
        if dot(n, A - centroid) < 0
            n = -n;                       % orient outward
        end
        if dot(n, -A) >= -1e-12          % origin on or outside this face
            inside = false;
            return;
        end
    end

end

function HRTFset = form_supdeq_input(field, cfg)
% SUpDEq uses [direction x frequency] spectra and polar elevation:
% elevation 0 deg is the north pole and 90 deg is the horizontal plane.

    nDirections = size(field.r, 1);
    maximumResolvableOrder = max(0, floor(sqrt(nDirections) - 1));

    if isfield(field, "fftLength") && ~isempty(field.fftLength)
        fftLength = field.fftLength;
    elseif ~isempty(cfg.fftLength)
        fftLength = cfg.fftLength;
    else
        fftLength = size(field.hrir, 3);
    end

    assert(isscalar(fftLength) && isfinite(fftLength), ...
        "SUpDEq requires a scalar FFT length.");

    fftOversize = fftLength / size(field.hrir, 3);
    assert(isscalar(fftOversize) && abs(fftOversize - round(fftOversize)) < eps, ...
        "cfg.fftLength must be an integer multiple of the processed HRIR length for SUpDEq.");

    HRTFset.HRTF_L = squeeze(field.complexHrtf(:, :, 1));
    HRTFset.HRTF_R = squeeze(field.complexHrtf(:, :, 2));
    HRTFset.f = field.freqHzWithDC;
    HRTFset.fs = field.fs;
    HRTFset.FFToversize = round(fftOversize);
    HRTFset.Nmax = min(cfg.supdeq.maxSHOrder, maximumResolvableOrder);
    HRTFset.samplingGrid = to_supdeq_sampling_grid(field.azElDeg);

end

function grid = to_supdeq_sampling_grid(azElDeg)

    azimuthDeg = mod(azElDeg(:, 1), 360);
    polarElevationDeg = 90 - azElDeg(:, 2);
    grid = [azimuthDeg, polarElevationDeg];

end

function complexHrtf = normalise_supdeq_output(left, right, ...
        nDirections, nFrequencyBins)

    left = orient_direction_major_spectra(left, nDirections);
    right = orient_direction_major_spectra(right, nDirections);

    assert(size(left, 2) >= nFrequencyBins && ...
        size(right, 2) >= nFrequencyBins, ...
        "SUpDEq returned fewer one-sided frequency bins than requested.");

    complexHrtf = cat(3, left(:, 1:nFrequencyBins), ...
        right(:, 1:nFrequencyBins));

end

function spectra = orient_direction_major_spectra(spectra, nDirections)

    if size(spectra, 1) == nDirections
        return;
    elseif size(spectra, 2) == nDirections
        spectra = spectra.';
    else
        error("SUpDEq output dimensions do not match the requested grid.");
    end

end
