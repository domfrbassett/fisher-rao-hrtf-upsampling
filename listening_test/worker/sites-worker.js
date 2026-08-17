"use strict";

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Cache-Control": "no-store",
  "Content-Security-Policy":
    "default-src 'self'; script-src 'self'; style-src 'self'; media-src 'self'; connect-src 'self'"
};

let schemaReady = null;

export default {
  async fetch(request, env, ctx) {
    try {
      await ensureSchema(env);
      const url = new URL(request.url);

      if (request.method === "GET" && url.pathname === "/api/health") {
        return sendJson(200, { ok: true, study: "fisher-rao-2ifc" });
      }
      if (request.method === "POST" && url.pathname === "/api/session/start") {
        return startSession(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/response") {
        return storeResponse(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/session/complete") {
        return completeSession(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/session/pause") {
        return pauseSession(request, env);
      }
      if (request.method === "GET" && url.pathname === "/api/export.csv") {
        return exportResponses(url, env);
      }
      if (request.method === "GET" || request.method === "HEAD") {
        return serveAsset(request, env);
      }
      return sendJson(404, { error: "Not found." });
    } catch (error) {
      console.error(error);
      return sendJson(500, { error: "Server error." });
    }
  }
};

async function ensureSchema(env) {
  if (!env.DB) {
    throw new Error("Missing D1 binding DB.");
  }
  if (!schemaReady) {
    schemaReady = env.DB.batch([
      env.DB.prepare(
        "CREATE TABLE IF NOT EXISTS sessions (" +
        "session_id TEXT PRIMARY KEY, participant_code TEXT NOT NULL, " +
        "entered_code TEXT, seed INTEGER NOT NULL, study_id TEXT, " +
        "manifest_version TEXT, data_json TEXT NOT NULL, started_at TEXT NOT NULL)"
      ),
      env.DB.prepare(
        "CREATE TABLE IF NOT EXISTS responses (" +
        "response_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, " +
        "participant_code TEXT, study_id TEXT, manifest_version TEXT, " +
        "track_id TEXT, data_json TEXT NOT NULL, received_at TEXT NOT NULL)"
      ),
      env.DB.prepare(
        "CREATE TABLE IF NOT EXISTS pauses (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, " +
        "participant_code TEXT, data_json TEXT NOT NULL, paused_at TEXT NOT NULL)"
      ),
      env.DB.prepare(
        "CREATE TABLE IF NOT EXISTS completions (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, " +
        "participant_code TEXT, data_json TEXT NOT NULL, completed_at TEXT NOT NULL)"
      ),
      env.DB.prepare("CREATE INDEX IF NOT EXISTS idx_responses_participant ON responses(participant_code, study_id, manifest_version)"),
      env.DB.prepare("CREATE INDEX IF NOT EXISTS idx_pauses_participant ON pauses(participant_code)")
    ]);
  }
  await schemaReady;
}

async function startSession(request, env) {
  const body = await readJsonBody(request);
  const enteredParticipantCode = sanitiseCode(body.participantCode);
  if (!enteredParticipantCode || !body.consentConfirmed || !body.headphonesConfirmed) {
    return sendJson(400, {
      error: "A participant code, consent confirmation and headphone confirmation are required."
    });
  }

  const participantCode = await resolveParticipantCode(env, enteredParticipantCode);
  const studyId = cleanText(body.studyId, 80);
  const manifestVersion = cleanText(body.manifestVersion, 80);
  const sessionId = `${new Date().toISOString().replace(/[:.]/g, "-")}_${randomHex(6)}`;
  const seed = crypto.getRandomValues(new Uint32Array(1))[0];
  const session = {
    sessionId,
    participantCode,
    enteredParticipantCode,
    resumeAliasUsed: enteredParticipantCode !== participantCode,
    seed,
    studyId,
    manifestVersion,
    startedAt: new Date().toISOString(),
    consentConfirmed: true,
    headphonesConfirmed: true,
    listeningEnvironment: cleanText(body.listeningEnvironment, 80),
    userAgent: cleanText(request.headers.get("user-agent") || "", 300),
    previousProgress: await getParticipantProgress(env, participantCode, studyId, manifestVersion)
  };
  await env.DB.prepare(
    "INSERT INTO sessions(session_id, participant_code, entered_code, seed, study_id, manifest_version, data_json, started_at) " +
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  ).bind(sessionId, participantCode, enteredParticipantCode, seed, studyId,
    manifestVersion, JSON.stringify(session), session.startedAt).run();
  return sendJson(201, session);
}

async function storeResponse(request, env) {
  const body = await readJsonBody(request);
  const sessionId = sanitiseSessionId(body.sessionId);
  const trialId = cleanText(body.trialId, 120);
  if (!sessionId || !trialId || !Number.isFinite(body.responseInterval)) {
    return sendJson(400, { error: "Invalid trial response." });
  }
  const responseId = `${sessionId}:${trialId}`;
  const existing = await env.DB.prepare(
    "SELECT response_id FROM responses WHERE response_id = ?"
  ).bind(responseId).first();
  if (existing) {
    return sendJson(200, { stored: true, duplicate: true });
  }

  const row = {
    responseId,
    sessionId,
    sessionKnown: await sessionExists(env, sessionId),
    participantCode: sanitiseCode(body.participantCode),
    studyId: cleanText(body.studyId, 80),
    manifestVersion: cleanText(body.manifestVersion, 80),
    assignedVirtualHrtfSubjectId: finiteOrNull(body.assignedVirtualHrtfSubjectId),
    trialId,
    blockId: cleanText(body.blockId, 80),
    blockType: cleanText(body.blockType, 40),
    difficultySection: cleanText(body.difficultySection, 40),
    axis: cleanText(body.axis, 40),
    pairId: cleanText(body.pairId, 100),
    trackId: cleanText(body.trackId, 140),
    virtualHrtfSubjectId: finiteOrNull(body.virtualHrtfSubjectId),
    fieldType: cleanText(body.fieldType, 60),
    method: cleanText(body.method, 80),
    retainedDirections: finiteOrNull(body.retainedDirections),
    repetition: finiteOrNull(body.repetition),
    adaptive: Boolean(body.adaptive),
    staircaseTrial: finiteOrNull(body.staircaseTrial),
    levelIndex: finiteOrNull(body.levelIndex),
    separationDeg: finiteOrNull(body.separationDeg),
    displacementSign: cleanText(body.displacementSign, 40),
    staircaseRule: cleanText(body.staircaseRule, 80),
    staircaseDirection: cleanText(body.staircaseDirection, 40),
    reversalCount: finiteOrNull(body.reversalCount),
    staircaseStopReason: cleanText(body.staircaseStopReason, 40),
    hardestLevelTrialCount: finiteOrNull(body.hardestLevelTrialCount),
    hardestLevelCorrectCount: finiteOrNull(body.hardestLevelCorrectCount),
    staircaseComplete: Boolean(body.staircaseComplete),
    thresholdEstimateDeg: finiteOrNull(body.thresholdEstimateDeg),
    intervalOneStimulus: cleanText(body.intervalOneStimulus, 40),
    intervalTwoStimulus: cleanText(body.intervalTwoStimulus, 40),
    correctInterval: finiteOrNull(body.correctInterval),
    responseInterval: finiteOrNull(body.responseInterval),
    correct: Boolean(body.correct),
    reactionTimeMs: finiteOrNull(body.reactionTimeMs),
    playbackCount: finiteOrNull(body.playbackCount),
    localAIRM: finiteOrNull(body.localAIRM),
    predictedDPrimeReference: finiteOrNull(body.predictedDPrimeReference),
    predictedDPrimeField: finiteOrNull(body.predictedDPrimeField),
    predictedDeltaDPrime: finiteOrNull(body.predictedDeltaDPrime),
    LSDdB: finiteOrNull(body.LSDdB),
    ILDErrorDb: finiteOrNull(body.ILDErrorDb),
    receivedAt: new Date().toISOString()
  };
  await env.DB.prepare(
    "INSERT INTO responses(response_id, session_id, participant_code, study_id, manifest_version, track_id, data_json, received_at) " +
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  ).bind(responseId, sessionId, row.participantCode, row.studyId,
    row.manifestVersion, row.trackId, JSON.stringify(row), row.receivedAt).run();
  return sendJson(201, { stored: true });
}

async function completeSession(request, env) {
  const body = await readJsonBody(request);
  const sessionId = sanitiseSessionId(body.sessionId);
  if (!sessionId || !(await sessionExists(env, sessionId))) {
    return sendJson(400, { error: "Invalid session." });
  }
  const row = {
    sessionId,
    participantCode: sanitiseCode(body.participantCode),
    assignedVirtualHrtfSubjectId: finiteOrNull(body.assignedVirtualHrtfSubjectId),
    completedAt: new Date().toISOString(),
    completedTrialCount: finiteOrNull(body.completedTrialCount)
  };
  await env.DB.prepare(
    "INSERT INTO completions(session_id, participant_code, data_json, completed_at) VALUES (?, ?, ?, ?)"
  ).bind(sessionId, row.participantCode, JSON.stringify(row), row.completedAt).run();
  return sendJson(201, { completed: true, completionCode: sessionId.slice(-12) });
}

async function pauseSession(request, env) {
  const body = await readJsonBody(request);
  const sessionId = sanitiseSessionId(body.sessionId);
  if (!sessionId || !(await sessionExists(env, sessionId))) {
    return sendJson(400, { error: "Invalid session." });
  }
  const row = {
    sessionId,
    participantCode: sanitiseCode(body.participantCode),
    assignedVirtualHrtfSubjectId: finiteOrNull(body.assignedVirtualHrtfSubjectId),
    pausedAt: new Date().toISOString(),
    completedTrialCount: finiteOrNull(body.completedTrialCount)
  };
  await env.DB.prepare(
    "INSERT INTO pauses(session_id, participant_code, data_json, paused_at) VALUES (?, ?, ?, ?)"
  ).bind(sessionId, row.participantCode, JSON.stringify(row), row.pausedAt).run();
  return sendJson(201, {
    paused: true,
    resumeCode: row.participantCode,
    resumeInstruction: "Resume by entering the same participant code used at the start."
  });
}

async function exportResponses(url, env) {
  const exportKey = env.EXPORT_KEY || "";
  if (exportKey && url.searchParams.get("key") !== exportKey) {
    return sendJson(403, { error: "Export key required." });
  }
  const result = await env.DB.prepare(
    "SELECT data_json FROM responses ORDER BY received_at, response_id"
  ).all();
  const records = (result.results || []).map((row) => JSON.parse(row.data_json));
  return new Response(toCsv(records), {
    status: 200,
    headers: {
      ...SECURITY_HEADERS,
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": "attachment; filename=\"two_ifc_responses.csv\""
    }
  });
}

async function getParticipantProgress(env, participantCode, studyId, manifestVersion) {
  const result = await env.DB.prepare(
    "SELECT data_json FROM responses WHERE participant_code = ? AND study_id = ? AND manifest_version = ? ORDER BY received_at"
  ).bind(participantCode, studyId, manifestVersion).all();
  const matching = (result.results || []).map((row) => JSON.parse(row.data_json));
  const completedTrackIds = [];
  let assignedVirtualHrtfSubjectId = null;
  for (const record of matching) {
    if (assignedVirtualHrtfSubjectId === null) {
      assignedVirtualHrtfSubjectId = finiteOrNull(record.assignedVirtualHrtfSubjectId);
      if (assignedVirtualHrtfSubjectId === null) {
        assignedVirtualHrtfSubjectId = finiteOrNull(record.virtualHrtfSubjectId);
      }
    }
    if (record.adaptive && record.staircaseComplete && record.trackId &&
        !completedTrackIds.includes(record.trackId)) {
      completedTrackIds.push(record.trackId);
    }
  }
  return {
    assignedVirtualHrtfSubjectId,
    completedTrackIds,
    completedTrackCount: completedTrackIds.length,
    previousResponseCount: matching.length
  };
}

async function resolveParticipantCode(env, enteredCode) {
  const exact = await env.DB.prepare(
    "SELECT response_id FROM responses WHERE participant_code = ? LIMIT 1"
  ).bind(enteredCode).first();
  if (exact) {
    return enteredCode;
  }
  const pauseResult = await env.DB.prepare(
    "SELECT session_id, participant_code FROM pauses ORDER BY id DESC"
  ).all();
  for (const record of pauseResult.results || []) {
    if (sanitiseSessionId(record.session_id).endsWith(enteredCode) ||
        sanitiseCode(record.participant_code) === enteredCode) {
      const participantCode = sanitiseCode(record.participant_code);
      if (participantCode) {
        return participantCode;
      }
    }
  }
  const sessionResult = await env.DB.prepare(
    "SELECT session_id, participant_code FROM sessions ORDER BY started_at DESC"
  ).all();
  for (const record of sessionResult.results || []) {
    if (sanitiseSessionId(record.session_id).endsWith(enteredCode)) {
      const participantCode = sanitiseCode(record.participant_code);
      if (participantCode) {
        return participantCode;
      }
    }
  }
  return enteredCode;
}

async function sessionExists(env, sessionId) {
  const row = await env.DB.prepare(
    "SELECT session_id FROM sessions WHERE session_id = ?"
  ).bind(sessionId).first();
  return Boolean(row);
}

async function serveAsset(request, env) {
  const url = new URL(request.url);
  const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
  let response = await env.ASSETS.fetch(new Request(new URL(pathname, url.origin), request));
  if (response.status === 404) {
    response = await env.ASSETS.fetch(new Request(new URL(`/public${pathname}`, url.origin), request));
  }
  if (response.status === 404 && !pathname.includes(".")) {
    response = await env.ASSETS.fetch(new Request(new URL(`${pathname}.html`, url.origin), request));
  }
  if (response.status === 404) {
    return sendJson(404, { error: "Not found." });
  }
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(request.method === "HEAD" ? null : response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

async function readJsonBody(request) {
  const raw = await request.text();
  if (raw.length > 1e6) {
    throw new Error("Request body is too large.");
  }
  return raw ? JSON.parse(raw) : {};
}

function sendJson(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...SECURITY_HEADERS, "Content-Type": "application/json; charset=utf-8" }
  });
}

function sanitiseCode(value) {
  return String(value || "").trim().replace(/[^A-Za-z0-9_-]/g, "").slice(0, 32);
}

function sanitiseSessionId(value) {
  return String(value || "").replace(/[^A-Za-z0-9_TZ.-]/g, "").slice(0, 80);
}

function cleanText(value, maximumLength) {
  return String(value ?? "").slice(0, maximumLength);
}

function finiteOrNull(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function randomHex(bytes) {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  return Array.from(data).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function toCsv(records) {
  if (records.length === 0) {
    return "";
  }
  const columns = [...new Set(records.flatMap((record) => Object.keys(record)))];
  const quote = (value) => {
    if (value === null || value === undefined) {
      return "";
    }
    const stringValue = String(value);
    return /[",\r\n]/.test(stringValue) ? `"${stringValue.replace(/"/g, "\"\"")}"` : stringValue;
  };
  return `${columns.join(",")}\n${records.map((record) =>
    columns.map((column) => quote(record[column])).join(",")).join("\n")}\n`;
}
