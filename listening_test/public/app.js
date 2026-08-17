"use strict";

const state = {
  configuration: null,
  manifest: null,
  session: null,
  blocks: [],
  blockIndex: -1,
  trialIndex: -1,
  adaptiveTrackIndex: -1,
  currentTrial: null,
  playbackCount: 0,
  responseEnabledAt: null,
  completedTrialCount: 0,
  audioContext: null,
  audioCache: new Map(),
  random: null,
  assignedVirtualHrtfSubjectId: null,
  resumeProgress: null
};

const LEGACY_PENDING_RESPONSES_KEY = "twoIfcPendingResponses";

const elements = {};

window.addEventListener("DOMContentLoaded", initialise);

async function initialise() {
  bindElements();
  bindActions();
  try {
    const requestedConfig = new URLSearchParams(window.location.search).get("config");
    const configPath = requestedConfig || "config/experiment.adaptive.json";
    state.configuration = await fetchJson(configPath);
    state.manifest = await fetchJson(state.configuration.manifest);
    document.title = state.configuration.title;
    elements.modePill.classList.add("hidden");
    showPanel("start");
  } catch (error) {
    elements.loadingPanel.querySelector("p").textContent =
      "The experiment configuration could not be loaded. Please inform the researcher.";
    console.error(error);
  }
}

function bindElements() {
  [
    "loading-panel", "start-panel", "calibration-panel", "instructions-panel",
    "trial-panel", "break-panel", "pause-panel", "complete-panel", "mode-pill",
    "participant-code", "environment", "consent-check", "headphones-check",
    "start-error", "begin-button", "calibration-button", "volume-check",
    "instructions-button", "instructions-text", "resume-notice",
    "start-block-button",
    "block-label", "progress-label", "progress-bar", "trial-question",
    "interval-one", "interval-two", "play-button", "replay-button",
    "answer-fieldset", "answer-one", "answer-two", "feedback", "next-button",
    "break-text", "continue-block-button", "pause-session-button",
    "pause-code", "completion-code",
    "participant-info-link"
  ].forEach((id) => {
    const name = id.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    elements[name] = document.getElementById(id);
  });
}

function bindActions() {
  elements.beginButton.addEventListener("click", beginSession);
  elements.calibrationButton.addEventListener("click", playCalibration);
  elements.volumeCheck.addEventListener("change", () => {
    elements.instructionsButton.disabled = !elements.volumeCheck.checked;
  });
  elements.instructionsButton.addEventListener("click", () => displayBlockInstructions(0));
  elements.startBlockButton.addEventListener("click", beginDisplayedBlock);
  elements.playButton.addEventListener("click", playCurrentTrial);
  elements.replayButton.addEventListener("click", playCurrentTrial);
  elements.answerOne.addEventListener("click", () => submitResponse(1));
  elements.answerTwo.addEventListener("click", () => submitResponse(2));
  elements.nextButton.addEventListener("click", advanceAfterResponse);
  elements.continueBlockButton.addEventListener("click", () => {
    displayBlockInstructions(state.blockIndex + 1);
  });
  elements.pauseSessionButton.addEventListener("click", pauseSession);
}

async function beginSession() {
  elements.startError.classList.add("hidden");
  const participantCode = elements.participantCode.value.trim();
  if (!participantCode || !elements.consentCheck.checked || !elements.headphonesCheck.checked) {
    elements.startError.textContent =
      "Please enter your participant code and confirm both statements.";
    elements.startError.classList.remove("hidden");
    return;
  }
  elements.beginButton.disabled = true;
  try {
    state.session = await postJson("/api/session/start", {
      participantCode,
      consentConfirmed: elements.consentCheck.checked,
      headphonesConfirmed: elements.headphonesCheck.checked,
      listeningEnvironment: elements.environment.value,
      studyId: state.manifest.studyId,
      manifestVersion: state.manifest.manifestVersion
    });
    state.random = mulberry32(state.session.seed);
    state.resumeProgress = state.session.previousProgress || null;
    state.blocks = prepareBlocks(state.manifest.blocks, state.random);
    await flushQueuedResponses();
    const resumedSession = state.resumeProgress &&
      state.resumeProgress.completedTrackCount > 0;
    if (resumedSession) {
      elements.resumeNotice.textContent =
        "Previous progress was found for this participant code. Please repeat the audio check before resuming at the next incomplete section.";
      elements.resumeNotice.classList.remove("hidden");
    } else {
      elements.resumeNotice.classList.add("hidden");
    }
    if (state.blocks.length === 0) {
      await finishSession();
      return;
    }
    elements.volumeCheck.checked = false;
    elements.instructionsButton.disabled = true;
    showPanel("calibration");
  } catch (error) {
    elements.startError.textContent =
      "The session could not be started. Please inform the researcher.";
    elements.startError.classList.remove("hidden");
    elements.beginButton.disabled = false;
  }
}

async function playCalibration() {
  elements.calibrationButton.disabled = true;
  const context = getAudioContext();
  await context.resume();
  await playBuffer(makeLeftRightCheckBuffer(context), context);
  elements.calibrationButton.disabled = false;
}

function displayBlockInstructions(blockIndex) {
  const block = state.blocks[blockIndex];
  if (!block) {
    finishSession();
    return;
  }
  state.blockIndex = blockIndex;
  elements.instructionsText.textContent = block.instruction;
  elements.startBlockButton.textContent =
    block.type === "practice" ? "Begin practice" : "Begin block";
  showPanel("instructions");
}

function beginDisplayedBlock() {
  state.trialIndex = 0;
  state.adaptiveTrackIndex = 0;
  displayTrial();
}

function displayTrial() {
  const block = state.blocks[state.blockIndex];
  if (block.adaptive) {
    const trackState = block.trackStates[state.adaptiveTrackIndex];
    state.currentTrial = makeAdaptiveTrial(block, trackState);
  } else {
    state.currentTrial = block.trials[state.trialIndex];
  }
  state.playbackCount = 0;
  state.responseEnabledAt = null;
  elements.blockLabel.textContent = block.label;
  if (block.adaptive) {
    const trackState = block.trackStates[state.adaptiveTrackIndex];
    elements.progressLabel.textContent =
      `Track ${state.adaptiveTrackIndex + 1} of ${block.trackStates.length}; comparison ${trackState.trialNumber + 1}`;
    elements.progressBar.max = block.trackStates.length;
    elements.progressBar.value = state.adaptiveTrackIndex;
  } else {
    elements.progressLabel.textContent =
      `Trial ${state.trialIndex + 1} of ${block.trials.length}`;
    elements.progressBar.max = block.trials.length;
    elements.progressBar.value = state.trialIndex;
  }
  elements.trialQuestion.textContent = block.question;
  elements.playButton.disabled = false;
  elements.playButton.classList.remove("hidden");
  elements.replayButton.classList.add("hidden");
  elements.replayButton.disabled = false;
  elements.answerFieldset.disabled = true;
  elements.feedback.className = "feedback hidden";
  elements.nextButton.classList.add("hidden");
  resetIntervalDisplay();
  showPanel("trial");
}

async function playCurrentTrial() {
  const block = state.blocks[state.blockIndex];
  const trial = state.currentTrial;
  elements.playButton.disabled = true;
  elements.replayButton.disabled = true;
  elements.answerFieldset.disabled = true;
  elements.feedback.className = "feedback hidden";
  resetIntervalDisplay();

  try {
    await preloadTrialAudio(trial);
    state.playbackCount += 1;
    elements.intervalOne.classList.add("playing");
    await playStimulus(trial.orderedStimuli[0].stimulus);
    elements.intervalOne.classList.remove("playing");
    await pause(state.configuration.intervalGapMs);
    elements.intervalTwo.classList.add("playing");
    await playStimulus(trial.orderedStimuli[1].stimulus);
    elements.intervalTwo.classList.remove("playing");

    state.responseEnabledAt = performance.now();
    elements.answerFieldset.disabled = false;
    elements.playButton.classList.add("hidden");
    if (block.type === "practice" && state.playbackCount === 1) {
      elements.replayButton.classList.remove("hidden");
      elements.replayButton.disabled = false;
    } else {
      elements.replayButton.classList.add("hidden");
    }
  } catch (error) {
    resetIntervalDisplay();
    elements.feedback.textContent =
      "A stimulus could not be loaded. Please inform the researcher.";
    elements.feedback.className = "feedback incorrect";
    elements.playButton.disabled = false;
    console.error(error);
  }
}

async function submitResponse(responseInterval) {
  if (!state.responseEnabledAt || elements.answerFieldset.disabled) {
    return;
  }
  const block = state.blocks[state.blockIndex];
  const trial = state.currentTrial;
  const correct = responseInterval === trial.correctInterval;
  const adaptiveUpdate = block.adaptive ? updateAdaptiveTrack(block, correct) : null;
  elements.answerFieldset.disabled = true;
  elements.replayButton.classList.add("hidden");

  const record = {
    responseId: `${state.session.sessionId}:${trial.trialId}`,
    sessionId: state.session.sessionId,
    participantCode: state.session.participantCode,
    studyId: state.manifest.studyId,
    manifestVersion: state.manifest.manifestVersion,
    assignedVirtualHrtfSubjectId: state.assignedVirtualHrtfSubjectId,
    trialId: trial.trialId,
    blockId: block.blockId,
    blockType: block.type,
    difficultySection: trial.difficultySection,
    axis: block.axis,
    pairId: trial.pairId,
    trackId: trial.trackId,
    virtualHrtfSubjectId: trial.virtualHrtfSubjectId,
    fieldType: trial.fieldType,
    method: trial.method,
    retainedDirections: trial.retainedDirections,
    repetition: trial.repetition,
    adaptive: Boolean(block.adaptive),
    staircaseTrial: trial.staircaseTrial,
    levelIndex: trial.levelIndex,
    separationDeg: trial.separationDeg,
    displacementSign: trial.displacementSign || null,
    staircaseRule: block.adaptiveRule ? block.adaptiveRule.rule : null,
    staircaseDirection: adaptiveUpdate ? adaptiveUpdate.direction : null,
    reversalCount: adaptiveUpdate ? adaptiveUpdate.reversalCount : null,
    staircaseStopReason: adaptiveUpdate ? adaptiveUpdate.stopReason : null,
    hardestLevelTrialCount: adaptiveUpdate ? adaptiveUpdate.hardestLevelTrials : null,
    hardestLevelCorrectCount: adaptiveUpdate ? adaptiveUpdate.hardestLevelCorrect : null,
    staircaseComplete: adaptiveUpdate ? adaptiveUpdate.complete : null,
    thresholdEstimateDeg: adaptiveUpdate ? adaptiveUpdate.thresholdEstimateDeg : null,
    intervalOneStimulus: trial.orderedStimuli[0].label,
    intervalTwoStimulus: trial.orderedStimuli[1].label,
    correctInterval: trial.correctInterval,
    responseInterval,
    correct,
    reactionTimeMs: Math.round(performance.now() - state.responseEnabledAt),
    playbackCount: state.playbackCount,
    localAIRM: trial.localAIRM,
    predictedDPrimeReference: trial.predictedDPrimeReference,
    predictedDPrimeField: trial.predictedDPrimeField,
    predictedDeltaDPrime: numberDifference(
      trial.predictedDPrimeField, trial.predictedDPrimeReference),
    LSDdB: trial.LSDdB,
    ILDErrorDb: trial.ILDErrorDb
  };
  queueResponse(record);
  await flushQueuedResponses();
  state.completedTrialCount += 1;

  if (block.type === "practice") {
    elements.feedback.textContent = correct ? "Correct." : "Incorrect. Listen for perceived position.";
    elements.feedback.className = `feedback ${correct ? "correct" : "incorrect"}`;
  }
  if (block.adaptive) {
    if (!adaptiveUpdate.complete) {
      elements.nextButton.textContent = "Next comparison";
    } else if (state.adaptiveTrackIndex + 1 < block.trackStates.length) {
      elements.nextButton.textContent = "Next track";
    } else {
      elements.nextButton.textContent = "Finish block";
    }
  } else {
    elements.nextButton.textContent =
      state.trialIndex + 1 < block.trials.length ? "Next trial" : "Finish block";
  }
  elements.nextButton.classList.remove("hidden");
}

function advanceAfterResponse() {
  const block = state.blocks[state.blockIndex];
  if (block.adaptive) {
    const trackState = block.trackStates[state.adaptiveTrackIndex];
    if (!trackState.complete) {
      displayTrial();
      return;
    }
    if (state.adaptiveTrackIndex + 1 < block.trackStates.length) {
      state.adaptiveTrackIndex += 1;
      displayTrial();
      return;
    }
    if (state.blockIndex + 1 < state.blocks.length) {
      elements.breakText.textContent =
        "This section is complete. You may continue now, or close the study and resume another time with the same participant code.";
      showPanel("break");
      return;
    }
    finishSession();
    return;
  }
  if (state.trialIndex + 1 < block.trials.length) {
    state.trialIndex += 1;
    displayTrial();
    return;
  }
  if (state.blockIndex + 1 < state.blocks.length) {
    elements.breakText.textContent =
      "This section is complete. You may continue now, or close the study and resume another time with the same participant code.";
    showPanel("break");
    return;
  }
  finishSession();
}

async function finishSession() {
  await flushQueuedResponses();
  try {
    const result = await postJson("/api/session/complete", {
      sessionId: state.session.sessionId,
      participantCode: state.session.participantCode,
      assignedVirtualHrtfSubjectId: state.assignedVirtualHrtfSubjectId,
      completedTrialCount: state.completedTrialCount
    });
    elements.completionCode.textContent = result.completionCode;
  } catch (error) {
    elements.completionCode.textContent = state.session.sessionId.slice(-12);
  }
  showPanel("complete");
}

async function pauseSession() {
  await flushQueuedResponses();
  elements.pauseSessionButton.disabled = true;
  try {
    const result = await postJson("/api/session/pause", {
      sessionId: state.session.sessionId,
      participantCode: state.session.participantCode,
      assignedVirtualHrtfSubjectId: state.assignedVirtualHrtfSubjectId,
      completedTrialCount: state.completedTrialCount
    });
    elements.pauseCode.textContent = result.resumeCode || state.session.participantCode;
  } catch (error) {
    elements.pauseCode.textContent = state.session.participantCode;
  }
  showPanel("pause");
}

function prepareBlocks(blocks, random) {
  const completedTrackIds = new Set(
    (state.resumeProgress && state.resumeProgress.completedTrackIds) || []);
  state.assignedVirtualHrtfSubjectId = null;
  return blocks.map((block) => {
    if (block.adaptive) {
      return prepareAdaptiveBlock(block, random, completedTrackIds);
    }
    const trials = shuffle(block.trials.slice(), random).map((sourceTrial) => {
      const targetFirst = random() < 0.5;
      const orderedStimuli = targetFirst ?
        [{ label: "target", stimulus: sourceTrial.stimuli.target },
          { label: "standard", stimulus: sourceTrial.stimuli.standard }] :
        [{ label: "standard", stimulus: sourceTrial.stimuli.standard },
          { label: "target", stimulus: sourceTrial.stimuli.target }];
      return {
        ...sourceTrial,
        orderedStimuli,
        correctInterval: targetFirst ? 1 : 2
      };
    });
    return { ...block, trials };
  }).filter((block) => !block.adaptive || block.trackStates.length > 0);
}

function prepareAdaptiveBlock(block, random, completedTrackIds = new Set()) {
  const adaptiveRule = block.adaptiveRule || state.manifest.adaptiveRule || {};
  const tracks = shuffle((block.tracks || [])
    .filter((track) => !completedTrackIds.has(track.trackId))
    .slice(), random).map((track) => {
    const levels = (track.levels || [])
      .slice()
      .sort((first, second) => Number(second.separationDeg) - Number(first.separationDeg));
    return {
      track,
      levels,
      currentLevelIndex: Math.min(
        Math.max(Number(adaptiveRule.startLevelIndex ?? 0), 0),
        Math.max(levels.length - 1, 0)),
      trialNumber: 0,
      consecutiveCorrect: 0,
      reversals: 0,
      lastDirection: null,
      hardestLevelTrials: 0,
      hardestLevelCorrect: 0,
      stopReason: null,
      complete: false,
      history: []
    };
  });
  return { ...block, adaptiveRule, trackStates: tracks };
}

function makeAdaptiveTrial(block, trackState) {
  const level = trackState.levels[trackState.currentLevelIndex];
  if (!level) {
    throw new Error(`Adaptive track has no level: ${trackState.track.trackId}`);
  }
  const usePositiveDisplacement = !level.stimuli.targetOpposite || state.random() < 0.5;
  const targetStimulus = usePositiveDisplacement ?
    level.stimuli.target : level.stimuli.targetOpposite;
  const targetFirst = state.random() < 0.5;
  const correctLabel = usePositiveDisplacement ? "target" : "standard";
  const orderedStimuli = targetFirst ?
    [{ label: "target", stimulus: targetStimulus },
      { label: "standard", stimulus: level.stimuli.standard }] :
    [{ label: "standard", stimulus: level.stimuli.standard },
      { label: "target", stimulus: targetStimulus }];
  return {
    ...trackState.track,
    ...level,
    trialId: `${trackState.track.trackId}_t${String(trackState.trialNumber + 1).padStart(2, "0")}_L${level.levelIndex}`,
    staircaseTrial: trackState.trialNumber + 1,
    repetition: trackState.trialNumber + 1,
    displacementSign: usePositiveDisplacement ? "positive" : "opposite",
    orderedStimuli,
    correctInterval: orderedStimuli.findIndex((item) => item.label === correctLabel) + 1
  };
}

function updateAdaptiveTrack(block, correct) {
  const rule = block.adaptiveRule || {};
  const trackState = block.trackStates[state.adaptiveTrackIndex];
  const trial = state.currentTrial;
  const levelBefore = trackState.currentLevelIndex;
  let direction = "same";
  let reversal = false;

  if (correct) {
    trackState.consecutiveCorrect += 1;
    const correctToDescend = trackState.reversals === 0 ?
      Number(rule.correctToDescendBeforeFirstReversal ?? rule.correctToDescend ?? 2) :
      Number(rule.correctToDescend ?? 2);
    if (trackState.consecutiveCorrect >= correctToDescend) {
      const nextLevel = Math.min(trackState.currentLevelIndex + 1, trackState.levels.length - 1);
      direction = nextLevel === trackState.currentLevelIndex ? "same" : "harder";
      trackState.currentLevelIndex = nextLevel;
      trackState.consecutiveCorrect = 0;
    }
  } else {
    const nextLevel = Math.max(trackState.currentLevelIndex - 1, 0);
    direction = nextLevel === trackState.currentLevelIndex ? "same" : "easier";
    trackState.currentLevelIndex = nextLevel;
    trackState.consecutiveCorrect = 0;
  }

  if (direction !== "same" && trackState.lastDirection && direction !== trackState.lastDirection) {
    trackState.reversals += 1;
    reversal = true;
  }
  if (direction !== "same") {
    trackState.lastDirection = direction;
  }

  const hardestLevelIndex = trackState.levels.length - 1;
  if (levelBefore === hardestLevelIndex) {
    trackState.hardestLevelTrials += 1;
    if (correct) {
      trackState.hardestLevelCorrect += 1;
    }
  }

  trackState.history.push({
    trialNumber: trial.staircaseTrial,
    levelIndex: levelBefore,
    separationDeg: trial.separationDeg,
    correct,
    direction,
    reversal
  });
  trackState.trialNumber += 1;

  const maxTrials = Number(rule.maxTrials ?? 10);
  const minTrials = Number(rule.minTrials ?? 6);
  const reversalsToStop = Number(rule.reversalsToStop ?? 6);
  const floorMinTrials = Number(rule.floorMinTrials ?? 8);
  const floorAccuracyToStop = Number(rule.floorAccuracyToStop ?? 0.875);
  const hardestAccuracy = trackState.hardestLevelTrials > 0 ?
    trackState.hardestLevelCorrect / trackState.hardestLevelTrials : 0;
  const floorCeilingReached = trackState.trialNumber >= minTrials &&
    trackState.hardestLevelTrials >= floorMinTrials &&
    hardestAccuracy >= floorAccuracyToStop;
  const reversalStopReached = trackState.trialNumber >= minTrials &&
    trackState.reversals >= reversalsToStop;
  const maxTrialsReached = trackState.trialNumber >= maxTrials;
  trackState.complete = floorCeilingReached || reversalStopReached || maxTrialsReached;
  if (floorCeilingReached) {
    trackState.stopReason = "floor_ceiling";
  } else if (reversalStopReached) {
    trackState.stopReason = "reversals";
  } else if (maxTrialsReached) {
    trackState.stopReason = "max_trials";
  }

  return {
    direction,
    reversal,
    reversalCount: trackState.reversals,
    stopReason: trackState.stopReason,
    hardestLevelTrials: trackState.hardestLevelTrials,
    hardestLevelCorrect: trackState.hardestLevelCorrect,
    complete: trackState.complete,
    thresholdEstimateDeg: estimateAdaptiveThreshold(trackState)
  };
}

function estimateAdaptiveThreshold(trackState) {
  const reversalSeparations = trackState.history
    .filter((item) => item.reversal)
    .slice(2)
    .map((item) => Number(item.separationDeg))
    .filter(Number.isFinite);
  const values = reversalSeparations.length >= 2 ? reversalSeparations :
    trackState.history
      .slice(Math.floor(trackState.history.length / 2))
      .map((item) => Number(item.separationDeg))
      .filter(Number.isFinite);
  if (values.length === 0) {
    return null;
  }
  values.sort((first, second) => first - second);
  const middle = Math.floor(values.length / 2);
  return values.length % 2 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
}

async function playStimulus(stimulus) {
  const context = getAudioContext();
  await context.resume();
  let buffer;
  if (stimulus.type === "wav") {
    buffer = await getAudioFileBuffer(stimulus.url, context);
  } else if (stimulus.type === "synthetic") {
    buffer = makeSyntheticBuffer(stimulus, context);
  } else {
    throw new Error(`Unsupported stimulus type: ${stimulus.type}`);
  }
  await playBuffer(buffer, context);
}

async function preloadTrialAudio(trial) {
  const context = getAudioContext();
  const fileStimuli = trial.orderedStimuli
    .map((item) => item.stimulus)
    .filter((stimulus) => stimulus.type === "wav");
  await Promise.all(fileStimuli.map((stimulus) =>
    getAudioFileBuffer(stimulus.url, context)));
}

function getAudioContext() {
  if (!state.audioContext) {
    state.audioContext = new (window.AudioContext || window.webkitAudioContext)({
      sampleRate: 48000
    });
  }
  return state.audioContext;
}

async function getAudioFileBuffer(url, context) {
  if (!state.audioCache.has(url)) {
    const response = await fetch(url, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Unable to load audio stimulus: ${url}`);
    }
    const raw = await response.arrayBuffer();
    state.audioCache.set(url, await context.decodeAudioData(raw));
  }
  return state.audioCache.get(url);
}

function makeSyntheticBuffer(stimulus, context) {
  const samplingRate = context.sampleRate;
  const samples = Math.round((stimulus.durationMs || 550) * samplingRate / 1000);
  const rampSamples = Math.round(0.02 * samplingRate);
  const delaySamples = Math.round(0.00055 * samplingRate *
    Math.sin((stimulus.azDeg || 0) * Math.PI / 180));
  const absoluteDelay = Math.abs(delaySamples);
  const buffer = context.createBuffer(2, samples + absoluteDelay, samplingRate);
  const left = buffer.getChannelData(0);
  const right = buffer.getChannelData(1);
  const random = mulberry32(stimulus.tokenSeed || 1);
  const level = stimulus.level || 0.1;
  const lateral = Math.sin((stimulus.azDeg || 0) * Math.PI / 180);
  const leftGain = level * Math.pow(10, (4 * lateral) / 20);
  const rightGain = level * Math.pow(10, (-4 * lateral) / 20);
  const elevationBlend = Math.max(-0.25, Math.min(0.25, (stimulus.elDeg || 0) / 180));
  let previousNoise = 0;

  for (let index = 0; index < samples; index += 1) {
    const noise = (2 * random()) - 1;
    const shaped = noise + elevationBlend * (noise - previousNoise);
    previousNoise = noise;
    const ramp = Math.min(1, index / rampSamples, (samples - index - 1) / rampSamples);
    const value = shaped * Math.max(0, ramp);
    const leftIndex = delaySamples < 0 ? index + absoluteDelay : index;
    const rightIndex = delaySamples > 0 ? index + absoluteDelay : index;
    left[leftIndex] += value * leftGain;
    right[rightIndex] += value * rightGain;
  }
  return buffer;
}

function makeLeftRightCheckBuffer(context) {
  const samplingRate = context.sampleRate;
  const burstSamples = Math.round(0.42 * samplingRate);
  const gapSamples = Math.round(0.28 * samplingRate);
  const rampSamples = Math.round(0.025 * samplingRate);
  const totalSamples = (2 * burstSamples) + gapSamples;
  const buffer = context.createBuffer(2, totalSamples, samplingRate);
  const left = buffer.getChannelData(0);
  const right = buffer.getChannelData(1);
  const level = state.configuration.calibrationLevel || 0.12;
  const random = mulberry32(314159);

  for (let index = 0; index < burstSamples; index += 1) {
    const ramp = Math.min(1, index / rampSamples, (burstSamples - index - 1) / rampSamples);
    const value = ((2 * random()) - 1) * level * Math.max(0, ramp);
    left[index] = value;
    right[index + burstSamples + gapSamples] = value;
  }
  return buffer;
}

function playBuffer(buffer, context) {
  return new Promise((resolve) => {
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    source.onended = resolve;
    source.start();
  });
}

function queueResponse(record) {
  const pending = getPendingResponses();
  pending.push(record);
  localStorage.setItem(pendingResponsesKey(), JSON.stringify(pending));
}

async function flushQueuedResponses() {
  const pending = getPendingResponses();
  while (pending.length > 0) {
    try {
      await postJson("/api/response", pending[0]);
      pending.shift();
      localStorage.setItem(pendingResponsesKey(), JSON.stringify(pending));
    } catch (error) {
      return;
    }
  }
}

function getPendingResponses() {
  try {
    return JSON.parse(localStorage.getItem(pendingResponsesKey()) || "[]");
  } catch (error) {
    return [];
  }
}

function pendingResponsesKey() {
  const manifestVersion = state.manifest && state.manifest.manifestVersion ?
    state.manifest.manifestVersion : "unknown";
  return `${LEGACY_PENDING_RESPONSES_KEY}:${manifestVersion}`;
}

function showPanel(name) {
  ["loading", "start", "calibration", "instructions", "trial", "break", "pause", "complete"]
    .forEach((panelName) => {
      elements[`${panelName}Panel`].classList.toggle("hidden", panelName !== name);
    });
}

function resetIntervalDisplay() {
  elements.intervalOne.classList.remove("playing");
  elements.intervalTwo.classList.remove("playing");
}

async function fetchJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Unable to load ${url}`);
  }
  return response.json();
}

async function postJson(url, payload) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    throw new Error(`Request failed: ${url}`);
  }
  return response.json();
}

function shuffle(values, random) {
  for (let index = values.length - 1; index > 0; index -= 1) {
    const swap = Math.floor(random() * (index + 1));
    [values[index], values[swap]] = [values[swap], values[index]];
  }
  return values;
}

function mulberry32(seed) {
  let value = seed >>> 0;
  return function random() {
    value += 0x6D2B79F5;
    let result = Math.imul(value ^ (value >>> 15), value | 1);
    result ^= result + Math.imul(result ^ (result >>> 7), result | 61);
    return ((result ^ (result >>> 14)) >>> 0) / 4294967296;
  };
}

function numberDifference(first, second) {
  return Number.isFinite(first) && Number.isFinite(second) ? first - second : null;
}

function pause(durationMs) {
  return new Promise((resolve) => window.setTimeout(resolve, durationMs));
}
