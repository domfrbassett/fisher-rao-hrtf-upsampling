function cleanup = activate_barumerli_compatibility(cfg)
% Activate local API compatibility adapters only while AMT evaluation is
% enabled; the AMT installation itself remains unmodified.

    root = string(cfg.toolbox.barumerliCompatibilityRoot);
    assert(isfolder(root), "Missing AMT compatibility adapter folder: %s", root);
    addpath(char(root), "-begin");
    clear rms;
    cleanup = onCleanup(@() deactivate_barumerli_compatibility(root));

end

function deactivate_barumerli_compatibility(root)

    if contains(string(path), root)
        rmpath(char(root));
    end
    clear rms;

end
