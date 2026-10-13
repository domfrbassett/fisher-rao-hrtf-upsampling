function sampling = create_sampling_conditions(dataset, cfg)
% Sparse sampling conditions from the comparator protocol: for each
% retention count, the fixed SONICOM direction indices shared by every
% method and subject.

    referenceR = dataset(1).r;

    for iSubject = 2:numel(dataset)
        assert(isequal(size(referenceR), size(dataset(iSubject).r)) && ...
            max(abs(referenceR - dataset(iSubject).r), [], "all") < ...
            cfg.uniqueDirectionTolerance, ...
            "All subjects must share the same direction grid for common sparse masks.");
    end

    counts = cfg.retentionConditions;
    assert(all(counts == fix(counts)) && all(counts >= 1) && ...
        all(counts <= size(referenceR, 1)), ...
        "cfg.retentionConditions must contain valid retained direction counts.");

    sampling = repmat(struct("retentionCount", [], "retainedIndices", []), ...
        1, numel(counts));

    for iCondition = 1:numel(counts)
        key = "N" + string(counts(iCondition));
        assert(isfield(cfg.comparatorProtocol.retainedIndices, key), ...
            "Comparator protocol does not contain retained indices for %s.", key);
        retained = cfg.comparatorProtocol.retainedIndices.(key);
        assert(all(retained >= 1) && all(retained <= size(referenceR, 1)), ...
            "Comparator protocol retained indices for %s are outside the loaded direction grid.", key);
        sampling(iCondition).retentionCount = counts(iCondition);
        sampling(iCondition).retainedIndices = sort(retained(:).');
    end

end
