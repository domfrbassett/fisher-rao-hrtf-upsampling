% run_hrtf_fisher_rao_hu_protocol.m
% Opt-in wrapper for the LAP/Hu sparse-mask comparator experiment used by
% the current manuscript.

protocolPath = fullfile(fileparts(mfilename("fullpath")), ...
    "ml_comparator_research", "comparator_protocol", "outputs", ...
    "hu_hrtfformer_protocol.json");

assert(isfile(protocolPath), ...
    "Protocol JSON not found. Run write_hu_protocol.py first: %s", protocolPath);

setenv("FISHERRAO_COMPARATOR_PROTOCOL_JSON", protocolPath);
run("run_hrtf_fisher_rao_evaluation.m");
