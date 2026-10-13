function run_evaluation(phase, subjectIds, resultsName)
% RUN_EVALUATION  Entry point for the reported 41-subject SONICOM
% comparison (common 16 kHz cue band, fail-closed reconstructions, complete
% model-generated RANF/FSP-AE fields, one combined run for all methods).
%
%   run_evaluation("smoke")               one subject, all methods, 20 observer
%                                         repetitions -> results/evaluation_smoke
%   run_evaluation("fisher")              all rows: signal metrics and Fisher
%                                         tensors, no observer
%                                         -> results/evaluation_sequential
%   run_evaluation("perceptual")          fill in the Barumerli observer (300
%                                         repetitions) for the rows completed by
%                                         the "fisher" phase
%   run_evaluation("full", ids, name)     signal, Fisher and observer (300
%                                         repetitions) for a subset of subjects,
%                                         written to results/<name>; used to split
%                                         the study across parallel MATLAB
%                                         processes (merge with
%                                         matlab/postprocessing/merge_worker_runs.m)
%   run_evaluation("tensors", ids, name)  signal metrics and Fisher tensors,
%                                         including the reference-template cross
%                                         terms, without the observer, for the
%                                         given subjects (all if empty), written to
%                                         results/<name> (default
%                                         evaluation_tensors); read by
%                                         scripts/template_matched_sensitivity.py
%
% The "fisher" and "perceptual" phases write to the same results folder and
% both resume from the checkpoint, so either can be interrupted and rerun.
% Settings are in matlab/fisher_rao_config.m.

    arguments
        phase (1, 1) string {mustBeMember(phase, ["smoke", "fisher", "perceptual", "full", "tensors"])}
        subjectIds double = []
        resultsName (1, 1) string = "evaluation"
    end

    root = string(fileparts(mfilename("fullpath")));
    addpath(char(fullfile(root, "matlab")));

    switch phase
        case "smoke"
            cfg = fisher_rao_config(ResultsName="evaluation_smoke", ...
                SubjectIds=10, RunPerceptual=true, PerceptualExperiments=20);
        case "fisher"
            cfg = fisher_rao_config(ResultsName="evaluation_sequential", ...
                RunPerceptual=false);
        case "perceptual"
            cfg = fisher_rao_config(ResultsName="evaluation_sequential", ...
                RunPerceptual=true, PerceptualOnly=true, ...
                PerceptualExperiments=300);
        case "tensors"
            if resultsName == "evaluation"
                resultsName = "evaluation_tensors";
            end
            cfg = fisher_rao_config(ResultsName=resultsName, ...
                SubjectIds=subjectIds, RunPerceptual=false);
        case "full"
            assert(~isempty(subjectIds), "Pass the subject IDs for this worker.");
            cfg = fisher_rao_config(ResultsName=resultsName, ...
                SubjectIds=subjectIds, RunPerceptual=true, ...
                PerceptualExperiments=300);
    end

    fprintf("run_evaluation(%s) started %s\n", phase, ...
        string(datetime("now")));
    run_fisher_rao_evaluation(cfg);
    fprintf("run_evaluation finished %s\n", string(datetime("now")));

end
