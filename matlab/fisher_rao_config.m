function cfg = fisher_rao_config(options)
% FISHER_RAO_CONFIG  Configuration of the reported evaluation.
%
%   cfg = fisher_rao_config()                     defaults of the paper
%   cfg = fisher_rao_config(Name=Value, ...)      with run options:
%
%   ResultsName            output folder under results/ (default "evaluation")
%   SubjectIds             subjects to evaluate; [] = the 41 protocol test subjects
%   RunPerceptual          run the Barumerli observer (default true)
%   PerceptualOnly         fill in only the observer columns of an existing
%                          run in the same results folder (default false)
%   PerceptualExperiments  observer repetitions per direction (default 300)
%   CueBandHz              common cue band (default 16000; Inf = full band)
%   DatasetRoot            SONICOM SOFA root (default dependencies/Sonicom_HRTFs)
%   ComparatorRoot         RANF/FSP-AE fields, <root>/<METHOD>/N###/Sonicom_<id>.sofa
%                          (default ml_sofas_without_node_replacement)
%
% Data convention used throughout the engine:
%   field.r           [Ndir x 3] unit Cartesian source directions
%   field.hrir        [Ndir x 2 x Nsamples] HRIRs
%   field.hrtfMag     [Ndir x Nfreq x 2] linear HRTF magnitudes
%   field.complexHrtf [Ndir x (Nfreq+1) x 2] one-sided complex HRTFs,
%                     including DC, for SUpDEq
%   field.fs          sampling rate in Hz

    arguments
        options.ResultsName (1, 1) string = "evaluation"
        options.SubjectIds double = []
        options.RunPerceptual (1, 1) logical = true
        options.PerceptualOnly (1, 1) logical = false
        options.PerceptualExperiments (1, 1) double {mustBeInteger, mustBePositive} = 300
        options.CueBandHz (1, 1) double = 16000
        options.DatasetRoot (1, 1) string = ""
        options.ComparatorRoot (1, 1) string = ""
    end

    studyRoot = string(fileparts(fileparts(mfilename("fullpath"))));
    dependencyRoot = fullfile(studyRoot, "dependencies");
    compatibilityRoot = fullfile(studyRoot, "matlab", "compatibility");

    %% Data, toolboxes and outputs

    cfg.datasetRoot = fullfile(dependencyRoot, "Sonicom_HRTFs");
    if strlength(options.DatasetRoot) > 0
        cfg.datasetRoot = options.DatasetRoot;
    end
    cfg.sofaFilePattern = "*_FreeFieldCompMinPhase_48kHz.sofa";
    cfg.resultsRoot = fullfile(studyRoot, "results", options.ResultsName);

    supdeqRoot = fullfile(dependencyRoot, "SUpDEq-master", "SUpDEq-master");
    cfg.toolbox.sofaRoot = fullfile(dependencyRoot, ...
        "SOFA Toolbox for Matlab and Octave 2.2.0", "SOFAtoolbox");
    cfg.toolbox.amtRoot = fullfile(dependencyRoot, ...
        "amtoolbox-full-1.6.0", "amtoolbox-1.6.0");
    cfg.toolbox.auditoryToolboxRoot = fullfile(dependencyRoot, "AuditoryToolbox");
    cfg.toolbox.supdeqRoot = supdeqRoot;
    cfg.toolbox.aktoolsRoot = fullfile(supdeqRoot, "thirdParty", "AKtools");
    cfg.toolbox.sofiaRoot = fullfile(supdeqRoot, "thirdParty", ...
        "SOFiA R13_MIT-License", "SOFiA");
    cfg.toolbox.sfsRoot = fullfile(supdeqRoot, "thirdParty", "sfs-matlab-2.5.0");
    cfg.toolbox.triangleRayIntersectionRoot = fullfile(supdeqRoot, ...
        "thirdParty", "TriangleRayIntersection");
    % Compatibility shims, see matlab/compatibility/README.md.
    cfg.toolbox.barumerliCompatibilityRoot = fullfile(compatibilityRoot, "amt_rms");
    cfg.toolbox.sfsCompatibilityRoot = fullfile(compatibilityRoot, "sfs_findvoronoi");

    %% Comparator protocol: subject split, sparse masks and methods

    protocolPath = fullfile(studyRoot, "ml_comparator_research", ...
        "comparator_protocol", "outputs", "hu_hrtfformer_protocol.json");
    assert(isfile(protocolPath), ...
        "Comparator protocol JSON does not exist: %s", protocolPath);
    protocol = jsondecode(fileread(protocolPath));

    cfg.randomSeed = 0;
    cfg.subjectIds = double(protocol.testSubjectIds(:)).';
    if ~isempty(options.SubjectIds)
        cfg.subjectIds = double(options.SubjectIds(:)).';
    end
    cfg.validationIds = cfg.subjectIds;
    cfg.retentionConditions = double(protocol.retentions(:)).';
    cfg.uniqueDirectionTolerance = 1e-10;

    retained = struct();
    for iCondition = 1:numel(cfg.retentionConditions)
        key = string(cfg.retentionConditions(iCondition));
        zeroBased = double(read_json_object_field( ...
            protocol.sonicomDirectionIndices, key));
        retained.("N" + key) = zeroBased(:).' + 1;
    end
    cfg.comparatorProtocol.retainedIndices = retained;

    cfg.methods = ["SUpDEq_SH", "SUpDEq_MCA", ...
        "SUpDEq_NN_MCA_6dB", "SUpDEq_Bary_MCA_6dB", ...
        "RANF", "FSP_AE"];

    cfg.externalComparators.alignedRoot = fullfile(studyRoot, ...
        "ml_sofas_without_node_replacement");
    if strlength(options.ComparatorRoot) > 0
        cfg.externalComparators.alignedRoot = options.ComparatorRoot;
    end
    assert(isfolder(cfg.externalComparators.alignedRoot), ...
        "RANF/FSP-AE comparator folder does not exist: %s", ...
        cfg.externalComparators.alignedRoot);

    %% HRTF spectra

    cfg.nFreqBins = 256;
    cfg.fftLength = 512;
    cfg.epsMag = 1e-8;

    % Common cue band. FSP-AE generates HRIRs at 32 kHz, so it carries no
    % content above 16 kHz. Every field (reference and reconstruction) is
    % therefore low-pass filtered with the same linear-phase FIR before any
    % Barumerli feature extraction (Fisher cues, observer template, observer
    % target), and the gammatone filterbank stops at the same frequency. The
    % FIR delay is identical for both ears and all directions, so ITD, ILD and
    % DTF shape are unaffected apart from the band limit.
    cfg.cueBand.limitHz = options.CueBandHz;
    cfg.cueBand.firOrder = 256;          % Kaiser beta 8: flat to 15 kHz, < -80 dB above 16 kHz
    cfg.cueBand.firCutoffHz = cfg.cueBand.limitHz - 500;
    cfg.cueBand.kaiserBeta = 8;
    cfg.signalBandHz = [20, 16000];      % Common LSD band for every method

    %% Fisher tensor

    % Barumerli PGE, ILD and MaxIACCe-transformed ITD features.
    cfg.fisher.featureSpace = "pge";
    cfg.fisher.cueConvention = "barumerli2023_pge_ild_maxiacce";
    cfg.sigmaMon = 1.25;              % dB, Barumerli PGE cue uncertainty
    cfg.sigmaILD = 1.0;               % dB, barumerli2023 model default
    cfg.sigmaITD = 0.569;             % transformed ITD scale
    cfg.shOrder = 6;                  % least-squares (pinv) SH fit of each cue

    % Per-cue-family Gram matrices J_f' J_f (and the cross terms
    % J_target' J_recon) at several SH orders, so noise-weight and SH-order
    % sensitivity analyses can be recomputed offline without re-extracting cues.
    cfg.export.shOrders = [4, 6, 8];

    % AIRM numerical settings
    cfg.eta = 1e-6;                   % Fixed SPD regularisation
    cfg.eigFloor = 1e-12;             % Roundoff safeguard only
    cfg.anisotropyThreshold = 1.10;   % Minimum ratio for orientation reporting
    cfg.informationFloor = 1e-10;     % For MAA reporting from unregularised tensor

    %% SUpDEq reconstruction

    cfg.headRadius = 0.0875;
    cfg.supdeq.maxSHOrder = 6;        % Reconstruction cap, independent of Fisher-field smoothing
    cfg.supdeq.tikhEps = 0;
    cfg.supdeq.publishedMcaDb = Inf;  % Setting used in the distributed MCA demo/paper configuration
    cfg.supdeq.variantMcDb = 6;       % Limited-boost NN/Bary variants
    cfg.supdeq.limitMC = true;
    cfg.supdeq.mcKnee = 0;
    cfg.supdeq.mcMinPhase = true;
    cfg.supdeq.limFade = "fadeDown";

    %% Bayesian observer (AMT barumerli2023)

    % Independent of the Fisher cues: DTF monaural features, MAP estimation
    % and the broader spectral uncertainty of the Hu/LAP calc_loc.m setup.
    cfg.runPerceptualModel = options.RunPerceptual;
    cfg.perceptual.featureSpace = "dtf";
    cfg.perceptual.numExperiments = options.PerceptualExperiments;
    cfg.perceptual.methods = cfg.methods;
    cfg.perceptual.retentionConditions = cfg.retentionConditions;
    cfg.perceptual.sigmaITD = cfg.sigmaITD;
    cfg.perceptual.sigmaILD = cfg.sigmaILD;
    cfg.perceptual.sigmaSpectral = 4.0;
    cfg.perceptual.sigmaPrior = 11.5;
    cfg.perceptual.sigmaMotor = 14.0;
    cfg.perceptual.estimator = "MAP";
    cfg.perceptual.randomSeed = cfg.randomSeed;
    cfg.perceptual.dtfConvention = "log";
    cfg.perceptual.experimentsPerBatch = 5; % Bound AMT posterior memory use
    % Report raw observer errors and, in addition, each reconstruction
    % relative to the dense measured HRTF evaluated against itself
    % (reconstruction minus self-reference).
    cfg.perceptual.reportRelativeToSelf = true;

    %% Execution: one row at a time, checkpointed and resumable

    cfg.execution.resume = true;
    cfg.execution.perceptualOnly = options.PerceptualOnly;
    if cfg.execution.perceptualOnly
        assert(cfg.runPerceptualModel, ...
            "Perceptual-only execution requires RunPerceptual=true.");
    end
    cfg.execution.checkpointMat = fullfile(cfg.resultsRoot, ...
        "full_evaluation_checkpoint.mat");
    cfg.execution.summaryCsv = fullfile(cfg.resultsRoot, ...
        "full_evaluation_summary.csv");
    cfg.execution.progressLog = fullfile(cfg.resultsRoot, ...
        "full_evaluation_progress.log");
    cfg.execution.writeCheckpointEveryRows = 1;
    cfg.execution.tensorRoot = fullfile(cfg.resultsRoot, "metric_tensors");
    cfg.execution.subjectSelectionCsv = fullfile(cfg.resultsRoot, ...
        "evaluation_subject_ids.csv");

end

function value = read_json_object_field(object, key)
% jsondecode must convert JSON keys such as "100" into valid MATLAB field
% names. Try the likely transforms without requiring a MATLAB-version-
% specific assumption.

    candidates = unique([key, "x" + key, matlab.lang.makeValidName(key)], ...
        "stable");
    for iCandidate = 1:numel(candidates)
        field = candidates(iCandidate);
        if isfield(object, field)
            value = object.(field);
            return;
        end
    end
    error("JSON object does not contain key %s.", key);

end
