function verify_configured_dependencies(cfg)
% Fail early with a precise message if the installed toolboxes are moved
% or an expected SUpDEq support function is absent.

    assert(isfolder(cfg.datasetRoot), ...
        "The SONICOM dataset folder does not exist: %s", cfg.datasetRoot);

    requiredFunctions = ["SOFAload", "supdeq_interpHRTF", "AKsht", ...
        "AKonsetDetect", "sofia_itc", "SFS_start", "TriangleRayIntersection", ...
        "ERBFilterBank"];

    for iFunction = 1:numel(requiredFunctions)
        assert(exist(requiredFunctions(iFunction), "file") ~= 0, ...
            "Required dependency function is unavailable: %s", ...
            requiredFunctions(iFunction));
    end

    requiredFisherFeatureFunctions = ["amt_start", "SOFAhrtf2dtf", ...
        "barumerli2023_featureextraction"];
    for iFunction = 1:numel(requiredFisherFeatureFunctions)
        assert(exist(requiredFisherFeatureFunctions(iFunction), "file") ~= 0, ...
            "Barumerli Fisher-feature dependency is unavailable: %s", ...
            requiredFisherFeatureFunctions(iFunction));
    end

    if cfg.runPerceptualModel
        requiredPerceptualFunctions = ["barumerli2023", "barumerli2023_metrics"];
        for iFunction = 1:numel(requiredPerceptualFunctions)
            assert(exist(requiredPerceptualFunctions(iFunction), "file") ~= 0, ...
                "Perceptual dependency function is unavailable: %s", ...
                requiredPerceptualFunctions(iFunction));
        end
    end

end
