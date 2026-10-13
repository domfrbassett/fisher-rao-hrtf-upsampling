function configure_toolbox_paths(cfg)
% Add the installed toolboxes without recursively adding SUpDEq's bundled
% copies of SOFA and AMT; the explicit project-local versions remain the
% selected versions for data loading and optional observer evaluation.

    configuredNames = ["sofaRoot", "amtRoot", "auditoryToolboxRoot", ...
        "supdeqRoot", "aktoolsRoot", "sofiaRoot", "sfsRoot", ...
        "triangleRayIntersectionRoot", "sfsCompatibilityRoot"];

    for iToolbox = 1:numel(configuredNames)
        toolboxPath = string(cfg.toolbox.(configuredNames(iToolbox)));
        assert(isfolder(toolboxPath), ...
            "Configured dependency folder does not exist: %s", toolboxPath);
    end

    addpath(genpath(char(cfg.toolbox.auditoryToolboxRoot)));

    addpath(char(cfg.toolbox.amtRoot));
    if exist("amt_start", "file") == 2
        amt_start('localonly', 'silent');
    end

    % Make the declared SUpDEq dependencies and SOFA version authoritative
    % after AMT initialises its own optional bundled toolboxes.
    addpath(char(cfg.toolbox.supdeqRoot));
    addpath(genpath(char(cfg.toolbox.aktoolsRoot)));
    addpath(genpath(char(cfg.toolbox.sofiaRoot)));
    addpath(genpath(char(cfg.toolbox.sfsRoot)));
    addpath(genpath(char(cfg.toolbox.triangleRayIntersectionRoot)));
    addpath(genpath(char(cfg.toolbox.sofaRoot)));
    % Shadow only the current-MATLAB-incompatible SFS helper. The external
    % SUpDEq repository remains unmodified.
    addpath(char(cfg.toolbox.sfsCompatibilityRoot), "-begin");
    clear findvoronoi;
    assert(startsWith(string(which("findvoronoi")), ...
        string(cfg.toolbox.sfsCompatibilityRoot)), ...
        "Project-local SFS compatibility override is not active.");
    remove_legacy_rms_shadow_paths;

end

function remove_legacy_rms_shadow_paths
% SFS and LTFAT bundle older rms.m variants that do not accept MATLAB's
% rms(...,'dim',n) call used by AMT barumerli2023_featureextraction.

    pathEntries = string(strsplit(path, pathsep));
    lowerEntries = lower(pathEntries);
    shadowsRms = contains(lowerEntries, "sfs_octave") | ...
        (contains(lowerEntries, "ltfat") & endsWith(lowerEntries, "sigproc"));
    pathsToRemove = unique(pathEntries(shadowsRms));

    for iPath = 1:numel(pathsToRemove)
        if contains(string(path), pathsToRemove(iPath))
            rmpath(char(pathsToRemove(iPath)));
        end
    end

    selectedRms = lower(string(which("rms")));
    assert(~contains(selectedRms, "sfs_octave") && ...
        ~contains(selectedRms, "ltfat"), ...
        "A legacy toolbox rms.m still shadows MATLAB rms: %s", selectedRms);

end
