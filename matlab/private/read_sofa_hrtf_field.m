function field = read_sofa_hrtf_field(filePath, cfg)
% Read one SimpleFreeFieldHRIR-like SOFA object through the SOFA Toolbox.

    sofa = SOFAload(char(filePath));

    assert(isfield(sofa, "Data") && isfield(sofa.Data, "IR"), ...
        "SOFA file does not contain Data.IR: %s", filePath);
    assert(isfield(sofa.Data, "SamplingRate"), ...
        "SOFA file does not contain Data.SamplingRate: %s", filePath);
    assert(isfield(sofa, "SourcePosition"), ...
        "SOFA file does not contain SourcePosition: %s", filePath);

    hrir = double(sofa.Data.IR);
    fs = double(sofa.Data.SamplingRate(1));

    assert(ndims(hrir) == 3 && size(hrir, 2) >= 2, ...
        "Expected Data.IR in [directions x receivers x samples] form.");
    hrir = hrir(:, 1:2, :);

    [r, azElDeg] = convert_sofa_positions(sofa);
    assert(size(hrir, 1) == size(r, 1), ...
        "SOFA HRIR count and SourcePosition count disagree in %s.", filePath);

    retained = unique_direction_indices(r, cfg.uniqueDirectionTolerance);

    field.r = r(retained, :);
    field.azElDeg = azElDeg(retained, :);
    field.hrir = hrir(retained, :, :);
    field.fs = fs;
    field.hasInterauralDelay = true;
    field.itdProvenance = "measured_hrir";
    if isfield(sofa.Data, "Delay") && ...
            size(sofa.Data.Delay, 1) == size(hrir, 1) && ...
            any(abs(double(sofa.Data.Delay(:))) > eps)
        delay = double(sofa.Data.Delay);
        field.hrir = incorporate_sofa_delay(field.hrir, ...
            delay(retained, :), fs);
        sofa.Data.Delay(:) = 0;
        field.itdProvenance = "hrir_with_sofa_delay_incorporated";
    end
    sofa.Data.IR = field.hrir;
    sofa.SourcePosition = sofa.SourcePosition(retained, :);
    if isfield(sofa.Data, "Delay") && ...
            size(sofa.Data.Delay, 1) == size(hrir, 1)
        sofa.Data.Delay = sofa.Data.Delay(retained, :);
    end
    field.sofaObject = SOFAupdateDimensions(sofa);

end

function hrir = incorporate_sofa_delay(hrir, delay, fs)
% Apply SOFA Data.Delay to HRIR samples once. External comparator exports
% may store delay in samples; very small fractional values are interpreted
% as seconds.
 
    delay = double(delay);
    if max(abs(delay(:))) < 1e-2 && any(abs(delay(:)) > eps)
        delaySamples = round(delay * fs);
    else
        delaySamples = round(delay);
    end
 
    nSamples = size(hrir, 3);
    nEars = min(size(hrir, 2), size(delaySamples, 2));
 
    for iDirection = 1:size(hrir, 1)
        for iEar = 1:nEars
            shift = delaySamples(iDirection, iEar);
            if shift > 0
                shift = min(shift, nSamples);
                hrir(iDirection, iEar, :) = cat(3, ...
                    zeros(1, 1, shift, "like", hrir), ...
                    hrir(iDirection, iEar, 1:(nSamples-shift)));
            elseif shift < 0
                shift = min(abs(shift), nSamples);
                hrir(iDirection, iEar, :) = cat(3, ...
                    hrir(iDirection, iEar, (shift+1):nSamples), ...
                    zeros(1, 1, shift, "like", hrir));
            end
        end
    end
 
end

function [r, azElDeg] = convert_sofa_positions(sofa)
% Return internal Cartesian directions and conventional azimuth/elevation.
% SUpDEq conversion to its polar-elevation convention is handled separately.

    positions = double(sofa.SourcePosition);
    positionType = "spherical";
    positionUnits = "degree";

    if isfield(sofa, "SourcePosition_Type")
        positionType = lower(string(sofa.SourcePosition_Type));
    end
    if isfield(sofa, "SourcePosition_Units")
        positionUnits = lower(string(sofa.SourcePosition_Units));
    end

    if contains(positionType, "spherical")

        azElDeg = positions(:, 1:2);

        if contains(positionUnits, "radian")
            azElDeg = rad2deg(azElDeg);
        end

        [x, y, z] = sph2cart(deg2rad(azElDeg(:, 1)), ...
            deg2rad(azElDeg(:, 2)), ones(size(azElDeg, 1), 1));
        r = [x, y, z];

    elseif contains(positionType, "cartesian")

        r = positions(:, 1:3);
        r = r ./ vecnorm(r, 2, 2);
        [az, el, ~] = cart2sph(r(:, 1), r(:, 2), r(:, 3));
        azElDeg = rad2deg([az, el]);

    else
        error("Unsupported SOFA SourcePosition_Type: %s", positionType);
    end

    r = r ./ vecnorm(r, 2, 2);

end

function retained = unique_direction_indices(r, tolerance)
% Suppress duplicate physical positions before fitting or interpolation.

    assert(tolerance > 0, "cfg.uniqueDirectionTolerance must be positive.");
    directionKey = round(r / tolerance);
    [~, retained] = unique(directionKey, "rows", "stable");
    retained = sort(retained);

end
