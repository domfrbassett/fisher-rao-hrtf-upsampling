function merge_worker_runs(workerNames)
% MERGE_WORKER_RUNS  Combine parallel worker folders results/<name> into
% results/evaluation.
%
% Workers are listed in priority order: if a subject x method x retention
% row appears in more than one worker (e.g. a worker that stopped part-way
% through a subject and was restarted elsewhere), the row from the LATER
% worker in the list is kept, and its tensor files overwrite the earlier
% copies. Rows from a subject that a later worker re-ran are taken entirely
% from that later worker, so no subject mixes rows from two processes.
%
% Checks that every row of the protocol is present exactly once and that
% all observer rows used 300 repetitions.

    if nargin < 1
        workerNames = "evaluation_w" + string(1:15);
    end
    root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
    outRoot = fullfile(root, "results", "evaluation");
    if ~isfolder(outRoot)
        mkdir(outRoot);
    end

    summary = table();
    for name = string(workerNames)
        workerRoot = fullfile(root, "results", name);
        csv = fullfile(workerRoot, "full_evaluation_summary.csv");
        if ~isfile(csv)
            fprintf("Skipping %s (no summary)\n", name);
            continue;
        end
        t = readtable(csv, "TextType", "string");
        t.sourceWorker = repmat(name, height(t), 1);
        if ~isempty(summary)
            % Later workers take precedence for any subject they contain.
            summary(ismember(summary.subjectId, unique(t.subjectId)), :) = [];
        end
        summary = [summary; t]; %#ok<AGROW>
        for sid = unique(t.subjectId).'
            src = fullfile(workerRoot, "metric_tensors", sprintf("subject_%04d", sid));
            dst = fullfile(outRoot, "metric_tensors", sprintf("subject_%04d", sid));
            if isfolder(dst)
                rmdir(dst, "s");
            end
            copyfile(src, dst);
        end
    end

    protocol = jsondecode(fileread(fullfile(root, "ml_comparator_research", ...
        "comparator_protocol", "outputs", "hu_hrtfformer_protocol.json")));
    nExpected = numel(protocol.testSubjectIds) * 6 * numel(protocol.retentions);
    keys = compose("%d|%d|%s", summary.subjectId, summary.retainedDirections, summary.method);
    assert(height(summary) == nExpected && numel(unique(keys)) == nExpected, ...
        "Expected %d unique rows, found %d rows (%d unique).", nExpected, ...
        height(summary), numel(unique(keys)));
    completed = summary.perceptualStatus == "completed";
    assert(all(summary.perceptualTrials(completed) == 300), ...
        "Some observer rows were not run with 300 repetitions.");

    summary = sortrows(summary, ["retainedDirections", "method", "subjectId"], ...
        ["descend", "ascend", "ascend"]);
    writetable(summary, fullfile(outRoot, "full_evaluation_summary.csv"));
    writetable(table(double(protocol.testSubjectIds(:)), 'VariableNames', {'subjectId'}), ...
        fullfile(outRoot, "evaluation_subject_ids.csv"));
    fprintf("Merged %d rows into %s\n", height(summary), outRoot);
end
