function [result, reconstructedFeatures, targetCueCache] = ...
    evaluate_fisher_tensor_airm(target, recon, cfg, targetCueCache)
% Evaluate reference and reconstructed HRTFs through their local
% Fisher information tensors and the AIRM distance.
%
% target and recon must be defined on the same unique physical grid.

    if nargin < 4
        targetCueCache = struct();
    end

    assert(isequal(size(target.r), size(recon.r)), ...
        "Target and reconstruction direction grids must match.");

    r = target.r;
    nDir = size(r, 1);

    %% Extract cue samples at measured directions

    if ~isfield(targetCueCache, "q")
        [targetCueCache.q, targetCueCache.itdMode] = ...
            extract_fisher_cues(target, target, cfg);
    end
    qTarget = targetCueCache.q;
    targetITDMode = targetCueCache.itdMode;
    [qRecon, reconstructedITDMode, reconstructedFeatures] = ...
        extract_fisher_cues(recon, target, cfg);

    assert(size(qTarget, 1) == nDir);
    assert(isequal(size(qTarget), size(qRecon)));

    %% Fit smooth spherical-harmonic cue fields

    shTarget = fit_sh_cue_field(r, qTarget, cfg);
    shRecon  = fit_sh_cue_field(r, qRecon,  cfg);

    %% Define cue-noise precision matrix

    nMonauralFeatures = size(qTarget, 2) - 2;
    assert(nMonauralFeatures >= 1, ...
        "Barumerli PGE extraction returned no monaural cue features.");

    sigma = [ ...
        repmat(cfg.sigmaMon, 1, nMonauralFeatures), ...
        cfg.sigmaILD, ...
        cfg.sigmaITD ...
    ];

    precision = diag(1 ./ (sigma .^ 2));

    %% Construct tangent-plane Fisher tensors

    gTarget = zeros(2, 2, nDir);
    gRecon  = zeros(2, 2, nDir);
    % Pole-stable analytical Cartesian SH gradients, as specified in the
    % methodology before projection onto a local tangent basis.
    [~, dYdx, dYdy, dYdz] = real_sh_basis_cartesian(r, cfg.shOrder);

    for n = 1:nDir

        rn = r(n, :).';
        V = local_tangent_basis(rn);
        JYCart = [dYdx(n, :).', dYdy(n, :).', dYdz(n, :).'];

        JCartTarget = shTarget.coefficients.' * JYCart;
        JCartRecon  = shRecon.coefficients.' * JYCart;

        JTarget = JCartTarget * V;
        JRecon  = JCartRecon * V;

        gTarget(:, :, n) = JTarget.' * precision * JTarget;
        gRecon(:, :, n)  = JRecon.'  * precision * JRecon;

        gTarget(:, :, n) = symmetrise(gTarget(:, :, n));
        gRecon(:, :, n)  = symmetrise(gRecon(:, :, n));

    end

    %% Compare tensor fields using regularised AIRM

    airm = zeros(nDir, 1);
    determinantError = zeros(nDir, 1);
    anisotropyError = zeros(nDir, 1);
    orientationError = nan(nDir, 1);

    targetMAA = nan(nDir, 2);
    reconMAA = nan(nDir, 2);

    for n = 1:nDir

        G = gTarget(:, :, n);
        Ghat = gRecon(:, :, n);

        Geta = G + cfg.eta * eye(2);
        GhatEta = Ghat + cfg.eta * eye(2);

        [airm(n), determinantError(n), anisotropyError(n), ...
            orientationError(n)] = compare_spd_tensors( ...
                Geta, GhatEta, cfg);

        targetMAA(n, :) = principal_axis_maa(G, cfg);
        reconMAA(n, :)  = principal_axis_maa(Ghat, cfg);

    end

    %% Directions where either tensor is effectively singular

    minEigTarget = zeros(nDir, 1);
    minEigRecon = zeros(nDir, 1);
    for n = 1:nDir
        minEigTarget(n) = min(eig(gTarget(:, :, n)));
        minEigRecon(n) = min(eig(gRecon(:, :, n)));
    end
    nearFloor = min(minEigTarget, minEigRecon) < 100 * cfg.eta;
    result.nearFloorProportion = mean(nearFloor);
    result.nearFloorByDirection = nearFloor;
    result.cueBandHz = cfg.cueBand.limitHz;

    %% Per-family Gram matrices at several SH orders (offline sensitivity)

    familyRows = {1:nMonauralFeatures, nMonauralFeatures + 1, ...
        nMonauralFeatures + 2};
    orders = cfg.export.shOrders;
    result.exportShOrders = orders;
    result.familyNames = ["monaural_pge", "ild", "itd"];
    result.targetFamilyGram = zeros(2, 2, nDir, 3, numel(orders));
    result.reconFamilyGram = zeros(2, 2, nDir, 3, numel(orders));
    % Unsymmetrised cross terms J_target' * J_recon per family: the sensitivity
    % of an observer that decodes reconstructed cues with reference templates.
    result.crossFamilyGram = zeros(2, 2, nDir, 3, numel(orders));
    for iOrder = 1:numel(orders)
        orderCfg = cfg;
        orderCfg.shOrder = orders(iOrder);
        fitT = fit_sh_cue_field(r, qTarget, orderCfg);
        fitR = fit_sh_cue_field(r, qRecon, orderCfg);
        [~, dX, dY, dZ] = real_sh_basis_cartesian(r, orders(iOrder));
        for n = 1:nDir
            V = local_tangent_basis(r(n, :).');
            JY = [dX(n, :).', dY(n, :).', dZ(n, :).'];
            JT = fitT.coefficients.' * JY * V;
            JR = fitR.coefficients.' * JY * V;
            for iFamily = 1:3
                rows = familyRows{iFamily};
                result.targetFamilyGram(:, :, n, iFamily, iOrder) = ...
                    symmetrise(JT(rows, :).' * JT(rows, :));
                result.reconFamilyGram(:, :, n, iFamily, iOrder) = ...
                    symmetrise(JR(rows, :).' * JR(rows, :));
                result.crossFamilyGram(:, :, n, iFamily, iOrder) = ...
                    JT(rows, :).' * JR(rows, :);
            end
        end
    end

    %% Summarise endpoints

    result.meanAIRM = mean(airm);
    result.medianAIRM = median(airm);
    result.stdAIRM = std(airm);
    result.iqrAIRM = iqr(airm);
    result.airmByDirection = airm;

    result.meanDeterminantError = mean(determinantError);
    result.determinantErrorByDirection = determinantError;

    result.meanAnisotropyError = mean(anisotropyError);
    result.anisotropyErrorByDirection = anisotropyError;

    validOrientation = ~isnan(orientationError);
    result.orientationErrorByDirection = orientationError;
    result.orientationValidCount = sum(validOrientation);
    result.orientationValidProportion = result.orientationValidCount / nDir;

    if any(validOrientation)
        result.meanOrientationErrorRad = mean(orientationError(validOrientation));
        result.meanOrientationErrorDeg = ...
            rad2deg(result.meanOrientationErrorRad);
    else
        result.meanOrientationErrorRad = NaN;
        result.meanOrientationErrorDeg = NaN;
    end

    result.targetTensor = gTarget;
    result.reconstructedTensor = gRecon;

    % Model-based local MAA values along each tensor's principal axes.
    result.targetPrincipalMAA = targetMAA;
    result.reconstructedPrincipalMAA = reconMAA;
    result.targetITDMode = targetITDMode;
    result.reconstructedITDMode = reconstructedITDMode;
    result.cueExtractionMode = cfg.fisher.cueConvention;
    result.status = "completed";
    result.message = "";

end

function [q, itdMode, features] = extract_fisher_cues(field, layoutField, cfg)
% Construct the deterministic Fisher cue vector with the Barumerli feature
% extractor: [PGE_left, PGE_right, ILD, transformed_ITD]. Every evaluated
% field (measured, SUpDEq or external comparator) is an HRIR field with
% interaural delays, so the ITD is the MaxIACCe-transformed ITD of AMT.

    assert(cfg.fisher.featureSpace == "pge", ...
        "The Fisher implementation requires Barumerli PGE features.");
    assert(isfield(field, "hasInterauralDelay") && ...
        field.hasInterauralDelay && ~isempty(field.hrir), ...
        "Fisher cue extraction requires an HRIR field with interaural delays.");
    featureDtf = convert_field_to_dtf_sofa(field, layoutField, cfg);
    features = barumerli2023_featureextraction(featureDtf, ...
        'target', char(cfg.fisher.featureSpace), 'fhigh', cue_band_fhigh(cfg));
    assert_barumerli_target_coordinates(features, layoutField.r, ...
        cfg.uniqueDirectionTolerance);

    monaural = double(features.monaural);
    ild = double(features.ild);
    itd = double(features.itd);
    itdMode = "barumerli_maxiacce";

    q = [monaural, ild, itd];
    assert(all(isfinite(q), "all"), ...
        "Barumerli cue extraction returned non-finite features.");

end

function model = fit_sh_cue_field(r, q, cfg)
% Fit each cue feature as a smooth real spherical-harmonic field.

    Y = real_sh_basis_cartesian(r, cfg.shOrder);
    coefficients = pinv(Y) * q;

    model.coefficients = coefficients;
    model.order = cfg.shOrder;

end

function V = local_tangent_basis(r)

    if abs(r(3)) > 0.9
        auxiliary = [0; 1; 0];
    else
        auxiliary = [0; 0; 1];
    end

    u1 = cross(auxiliary, r);
    u1 = u1 / norm(u1);

    u2 = cross(r, u1);
    u2 = u2 / norm(u2);

    V = [u1, u2];

end

function [dAIRM, detError, anisError, orientError] = ...
    compare_spd_tensors(G, Ghat, cfg)

    G = symmetrise(G);
    Ghat = symmetrise(Ghat);
    assert(all(isfinite(G), "all") && all(isfinite(Ghat), "all"), ...
        "Non-finite Fisher tensor reached the AIRM comparison.");

    %% AIRM distance using Cholesky congruence

    L = chol(G, "lower");

    S = L \ (Ghat / L.');
    S = symmetrise(S);

    lambda = eig(S);
    lambda = max(lambda, cfg.eigFloor);

    dAIRM = sqrt(sum(log(lambda) .^ 2));

    %% Scale difference

    detError = abs(log(det(Ghat) / det(G)));

    %% Anisotropy and orientation

    [V, mu] = eig(G, "vector");
    [Vhat, muHat] = eig(Ghat, "vector");

    [mu, order] = sort(mu, "descend");
    V = V(:, order);

    [muHat, orderHat] = sort(muHat, "descend");
    Vhat = Vhat(:, orderHat);

    ratio = mu(1) / mu(2);
    ratioHat = muHat(1) / muHat(2);

    anisError = abs(log(ratioHat / ratio));

    if ratio >= cfg.anisotropyThreshold && ...
            ratioHat >= cfg.anisotropyThreshold

        dotProduct = abs(V(:, 1).' * Vhat(:, 1));
        dotProduct = min(max(dotProduct, 0), 1);

        orientError = acos(dotProduct);

    else
        orientError = NaN;
    end

end

function maa = principal_axis_maa(G, cfg)
% Model-based local MAA along the principal axes of the unregularised
% Fisher tensor. Values are reported only where the tensor is informative
% in both tangent directions.

    G = symmetrise(G);

    mu = eig(G);
    mu = sort(mu, "descend");

    if min(mu) <= cfg.informationFloor
        maa = [NaN, NaN];
        return;
    end

    maa = 1 ./ sqrt(mu).';

end

function A = symmetrise(A)

    A = 0.5 * (A + A.');

end
