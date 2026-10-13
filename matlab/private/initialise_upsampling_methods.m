function upsamplers = initialise_upsampling_methods(cfg)
% The six reported methods. The distributed SUpDEq MCA demo defines MCA as
% SUpDEq preprocessing, SH interpolation, and magnitude correction with
% unlimited boost; the NN and Bary variants use a 6 dB boost limit. RANF and
% FSP-AE are read from their exported SOFA files.

    upsamplers = repmat(struct( ...
        "name", "", "preprocessing", "", "interpolation", "", ...
        "magnitudeCorrectionDb", NaN), ...
        1, numel(cfg.methods));

    for iMethod = 1:numel(cfg.methods)

        methodName = string(cfg.methods(iMethod));
        upsamplers(iMethod).name = methodName;

        switch methodName
            case "SUpDEq_SH"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "SH";
            case "SUpDEq_MCA"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "SH";
                upsamplers(iMethod).magnitudeCorrectionDb = cfg.supdeq.publishedMcaDb;
            case "SUpDEq_NN_MCA_6dB"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "NN";
                upsamplers(iMethod).magnitudeCorrectionDb = cfg.supdeq.variantMcDb;
            case "SUpDEq_Bary_MCA_6dB"
                upsamplers(iMethod).preprocessing = "SUpDEq";
                upsamplers(iMethod).interpolation = "Bary";
                upsamplers(iMethod).magnitudeCorrectionDb = cfg.supdeq.variantMcDb;
            case "RANF"
                upsamplers(iMethod).preprocessing = "ExternalSOFA";
                upsamplers(iMethod).interpolation = "RANF";
            case "FSP_AE"
                upsamplers(iMethod).preprocessing = "ExternalSOFA";
                upsamplers(iMethod).interpolation = "FSP_AE";
            otherwise
                error("Unrecognised interpolation method: %s", methodName);
        end
    end

end
