function recon = guard_finite_reconstruction(recon, sparseField, targetR, method)
% Fail closed: a reconstruction with any non-finite HRIR sample is not
% evaluated. Previously such fields propagated NaN into the cue features,
% where the eigenvalue floor and max(.,eps) guards silently converted them
% into constant, subject-independent metric values.

    nonFinite = any(~isfinite(recon.hrir), [2, 3]);
    silentEar = any(all(recon.hrir == 0, 3), 2);
    nonFinite = nonFinite | silentEar;
    recon.nonFiniteDirections = sum(nonFinite);
    if any(nonFinite)
        count = sum(nonFinite);
        recon = unavailable_reconstruction(sparseField, targetR, method.name, ...
            sprintf("Not applicable: %s returned non-finite or all-zero " + ...
            "HRIRs at %d of %d directions.", method.name, count, ...
            numel(nonFinite)));
        recon.nonFiniteDirections = count;
        recon.barycentricFallbackCount = NaN;
    end

end
