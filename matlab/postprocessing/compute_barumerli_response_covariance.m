function compute_barumerli_response_covariance(numExperiments)
% COMPUTE_BARUMERLI_RESPONSE_COVARIANCE  Local response covariance of the
% Barumerli (2023) MAP observer for the dense measured HRTFs of the 41
% held-out SONICOM subjects, at the directions plotted in the CRB figure.
%
% Uses the same observer configuration as the main evaluation: DTF
% features, common 16 kHz cue band, sigma_itd 0.569, sigma_ild 1 dB,
% sigma_spectral 4 dB, sigma_prior 11.5 deg, sigma_motor 14 deg, MAP.
% Responses are mapped into the same local tangent basis as the Fisher
% tensors (u1 = increasing azimuth, u2 = increasing elevation) with the
% spherical log map; only local responses (great-circle error < 45 deg) are
% used, so front-back and quadrant confusions do not inflate the covariance.
%
% Output: results/audits/barumerli_response_covariance_16k.mat

    if nargin < 1
        numExperiments = 300;
    end
    root = string(fileparts(mfilename("fullpath")));
    root = fileparts(fileparts(root));            % matlab/postprocessing -> project
    deps = fullfile(root, "dependencies");
    addpath(fullfile(deps, "amtoolbox-full-1.6.0", "amtoolbox-1.6.0"));
    amt_start('localonly', 'silent');
    addpath(genpath(fullfile(deps, "SOFA Toolbox for Matlab and Octave 2.2.0", "SOFAtoolbox")));
    entries = string(strsplit(path, pathsep));
    shadow = contains(lower(entries), "sfs_octave") | ...
        (contains(lower(entries), "ltfat") & endsWith(lower(entries), "sigproc"));
    for e = entries(shadow)
        rmpath(char(e));
    end
    addpath(char(fullfile(root, "matlab", "compatibility", "amt_rms")), "-begin");
    clear rms;

    protocol = jsondecode(fileread(fullfile(root, "ml_comparator_research", ...
        "comparator_protocol", "outputs", "hu_hrtfformer_protocol.json")));
    subjects = double(protocol.testSubjectIds(:)).';
    plotted = readmatrix(fullfile(root, "matlab", "postprocessing", "plotted_directions.csv"));

    rng(0, "twister");
    nSub = numel(subjects);
    nDir = size(plotted, 1);
    covariance = nan(2, 2, nDir, nSub);
    localFraction = nan(nDir, nSub);
    meanErrorTangentDeg = nan(2, nDir, nSub);
    b = fir1(256, 15500 / 24000, kaiser(257, 8));

    for iSub = 1:nSub
        id = subjects(iSub);
        file = dir(fullfile(deps, "Sonicom_HRTFs", "**", ...
            sprintf("P%04d_FreeFieldCompMinPhase_48kHz.sofa", id)));
        assert(isscalar(file), "SOFA for subject %d not found.", id);
        sofa = SOFAload(fullfile(file.folder, file.name));
        assert(all(abs(sofa.Data.Delay(:)) < eps), "Unexpected Data.Delay.");
        assert(sofa.Data.SamplingRate == 48000);
        ir = double(sofa.Data.IR);
        ir = filter(b, 1, cat(3, ir, zeros(size(ir, 1), size(ir, 2), 256)), [], 3);
        sofa.Data.IR = ir;
        sofa = SOFAupdateDimensions(sofa);
        dtf = SOFAhrtf2dtf(sofa, 'log');

        template = barumerli2023_featureextraction(dtf, 'template', 'dtf', 'fhigh', 16e3);
        target = barumerli2023_featureextraction(dtf, 'target', 'dtf', 'fhigh', 16e3);
        tc = target.coords.return_positions('cartesian');
        tc = tc ./ vecnorm(tc, 2, 2);
        pc = [cosd(plotted(:,2)).*cosd(plotted(:,1)), ...
              cosd(plotted(:,2)).*sind(plotted(:,1)), sind(plotted(:,2))];
        [~, idx] = max(pc * tc.', [], 2);
        sub.itd = target.itd(idx, :);
        sub.ild = target.ild(idx, :);
        sub.monaural = target.monaural(idx, :);
        sub.coords = [];

        responses = zeros(nDir, 0, 3);
        remaining = numExperiments;
        while remaining > 0
            n = min(25, remaining);
            [~, doa] = barumerli2023('template', template, 'target', sub, ...
                'num_exp', n, 'sigma_itd', 0.569, 'sigma_ild', 1, ...
                'sigma_spectral', 4, 'sigma_prior', 11.5, ...
                'sigma_motor', 14, 'MAP');
            responses = cat(2, responses, doa.estimations);
            remaining = remaining - n;
        end

        for d = 1:nDir
            r0 = tc(idx(d), :).';
            V = tangent_basis(r0);
            R = squeeze(responses(d, :, :));
            R = R ./ vecnorm(R, 2, 2);
            cosang = min(max(R * r0, -1), 1);
            ang = acos(cosang);
            local = rad2deg(ang) < 45;
            P = R - cosang * r0.';                 % tangent component
            nrm = vecnorm(P, 2, 2);
            scale = ang ./ max(nrm, eps);
            logmap = (P .* scale) * V;             % radians in (u1, u2)
            logmapDeg = rad2deg(logmap(local, :));
            localFraction(d, iSub) = mean(local);
            if sum(local) >= 10
                covariance(:, :, d, iSub) = cov(logmapDeg);
                meanErrorTangentDeg(:, d, iSub) = mean(logmapDeg, 1).';
            end
        end
        fprintf("Subject %d (%d/%d) done %s\n", id, iSub, nSub, string(datetime("now")));
    end

    plottedAzElDeg = plotted;
    out = fullfile(root, "results", "audits", "barumerli_response_covariance_16k.mat");
    save(out, "subjects", "plottedAzElDeg", "covariance", "localFraction", ...
        "meanErrorTangentDeg", "numExperiments", "-v7.3");
    fprintf("Wrote %s\n", out);
end

function V = tangent_basis(r)
    if abs(r(3)) > 0.9
        a = [0; 1; 0];
    else
        a = [0; 0; 1];
    end
    u1 = cross(a, r); u1 = u1 / norm(u1);
    u2 = cross(r, u1); u2 = u2 / norm(u2);
    V = [u1, u2];
end
