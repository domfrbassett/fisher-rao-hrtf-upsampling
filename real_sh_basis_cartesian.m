function [Y, dY_dx, dY_dy, dY_dz] = real_sh_basis_cartesian(r, order)
%REAL_SH_BASIS_CARTESIAN Real spherical harmonics and Cartesian gradients.
%
%   [Y, dY_dx, dY_dy, dY_dz] = real_sh_basis_cartesian(r, order)
%
% Inputs
%   r       [Ndir x 3] Cartesian directions. Non-unit inputs are
%           normalised before evaluation.
%   order   Maximum spherical-harmonic degree.
%
% Outputs
%   Y       [Ndir x (order+1)^2] real spherical-harmonic basis values.
%   dY_dx   Cartesian derivatives of the homogeneous solid-harmonic
%   dY_dy   extension. When projected onto a tangent basis on the unit
%   dY_dz   sphere, these give the surface derivatives of Y.
%
% Basis convention
%   Coefficients are ordered degree-by-degree, with m = -n:n within
%   degree n. The real basis removes the Condon--Shortley phase and uses
%   sine terms for negative order and cosine terms for positive order:
%
%       m < 0: sqrt(2) N_nm P_n^|m|(cos(theta)) sin(|m| phi)
%       m = 0:         N_n0 P_n^0(cos(theta))
%       m > 0: sqrt(2) N_nm P_n^m(cos(theta)) cos(m phi)
%
%   The implementation uses regular solid-harmonic polynomials in x, y,
%   and z, and is therefore stable at the poles.

    arguments
        r (:, 3) double
        order (1, 1) double {mustBeInteger, mustBeNonnegative}
    end

    norms = vecnorm(r, 2, 2);
    if any(norms <= eps)
        error("Directions must be non-zero Cartesian vectors.");
    end

    r = r ./ norms;
    x = r(:, 1);
    y = r(:, 2);
    z = r(:, 3);
    w = x + 1i * y;

    nDir = size(r, 1);
    nCoeffs = (order + 1)^2;
    Y = zeros(nDir, nCoeffs);
    dY_dx = zeros(nDir, nCoeffs);
    dY_dy = zeros(nDir, nCoeffs);
    dY_dz = zeros(nDir, nCoeffs);

    idx = 1;
    for n = 0:order
        pn = legendre_polynomial_coefficients(n);

        for m = -n:n
            absM = abs(m);
            derivPoly = polynomial_derivative(pn, absM);
            zPart = polyval(derivPoly, z);
            dzPart = polyval(polyder_safe(derivPoly), z);

            if absM == 0
                solid = zPart;
                dSolid_dx = zeros(nDir, 1);
                dSolid_dy = zeros(nDir, 1);
                dSolid_dz = dzPart;
                trigScale = 1;
            else
                wPower = w .^ absM;
                wDerivative = absM .* w .^ (absM - 1);
                complexSolid = zPart .* wPower;

                if m < 0
                    solid = imag(complexSolid);
                    dSolid_dx = imag(zPart .* wDerivative);
                    dSolid_dy = imag(1i .* zPart .* wDerivative);
                    dSolid_dz = imag(dzPart .* wPower);
                else
                    solid = real(complexSolid);
                    dSolid_dx = real(zPart .* wDerivative);
                    dSolid_dy = real(1i .* zPart .* wDerivative);
                    dSolid_dz = real(dzPart .* wPower);
                end

                trigScale = sqrt(2);
            end

            normalisation = sqrt( ...
                (2 * n + 1) * factorial(n - absM) / ...
                (4 * pi * factorial(n + absM)));
            scale = trigScale * normalisation;

            Y(:, idx) = scale .* solid;
            dY_dx(:, idx) = scale .* dSolid_dx;
            dY_dy(:, idx) = scale .* dSolid_dy;
            dY_dz(:, idx) = scale .* dSolid_dz;
            idx = idx + 1;
        end
    end

end

function pn = legendre_polynomial_coefficients(n)
% Return coefficients of the ordinary Legendre polynomial P_n(z).

    if n == 0
        pn = 1;
        return;
    elseif n == 1
        pn = [1, 0];
        return;
    end

    pNm2 = 1;
    pNm1 = [1, 0];

    for degree = 2:n
        zPNm1 = [pNm1, 0];
        pNm2Padded = [zeros(1, numel(zPNm1) - numel(pNm2)), pNm2];
        pn = ((2 * degree - 1) .* zPNm1 - ...
            (degree - 1) .* pNm2Padded) ./ degree;
        pNm2 = pNm1;
        pNm1 = pn;
    end

end

function derivative = polynomial_derivative(polynomial, derivativeOrder)

    derivative = polynomial;
    for iDerivative = 1:derivativeOrder
        derivative = polyder_safe(derivative);
    end

end

function derivative = polyder_safe(polynomial)

    if isscalar(polynomial)
        derivative = 0;
    else
        derivative = polyder(polynomial);
    end

end
