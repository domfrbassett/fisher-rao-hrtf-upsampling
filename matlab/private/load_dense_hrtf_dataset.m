function dataset = load_dense_hrtf_dataset(cfg)
% Load measured HRIR sets from SOFA files. The loader deliberately keeps
% measured HRIRs and Cartesian locations together: later interpolation is
% evaluated on the full measured direction grid.

    assert(~startsWith(string(cfg.datasetRoot), "PATH_TO_"), ...
        "Set cfg.datasetRoot to the directory containing the SOFA files.");
    assert(isfolder(cfg.datasetRoot), ...
        "The configured dataset directory does not exist: %s", cfg.datasetRoot);
    assert(exist("SOFAload", "file") == 2, ...
        "SOFAload was not found. Set cfg.toolbox.sofaRoot to a SOFA Toolbox installation.");

    files = dir(fullfile(char(cfg.datasetRoot), "**", char(cfg.sofaFilePattern)));
    assert(~isempty(files), ...
        "No SOFA files matching %s were found beneath %s.", ...
        cfg.sofaFilePattern, cfg.datasetRoot);

    dataset = struct([]);

    for iFile = 1:numel(files)

        filePath = string(fullfile(files(iFile).folder, files(iFile).name));
        subjectId = parse_subject_id(files(iFile).name);

        if ~isempty(cfg.subjectIds) && ...
                (isnan(subjectId) || ~ismember(subjectId, cfg.subjectIds))
            continue;
        end

        field = read_sofa_hrtf_field(filePath, cfg);
        field.subjectId = subjectId;
        field.filePath = filePath;

        if isempty(dataset)
            dataset = field;
        else
            dataset(end + 1) = field; %#ok<AGROW>
        end

    end

    assert(~isempty(dataset), ...
        "No SOFA files remained after applying cfg.subjectIds.");

end

function subjectId = parse_subject_id(fileName)
% SONICOM names begin P0001, P0002, and so forth. Do not infer the subject
% from a later acquisition-rate token such as the 48 in "_48kHz".

    token = regexp(fileName, "^P(\d+)", "tokens", "once");

    if isempty(token)
        subjectId = NaN;
    else
        subjectId = str2double(token{1});
    end

end
