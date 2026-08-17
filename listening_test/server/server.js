"use strict";

const http = require("node:http");
const path = require("node:path");
const fs = require("node:fs");
const fsp = require("node:fs/promises");
const crypto = require("node:crypto");
const { URL } = require("node:url");

const projectRoot = path.resolve(__dirname, "..");
const publicRoot = path.join(projectRoot, "public");
const dataRoot = path.join(__dirname, "data");
const responseFile = path.join(dataRoot, "responses.ndjson");
const completionFile = path.join(dataRoot, "completions.ndjson");
const pauseFile = path.join(dataRoot, "pauses.ndjson");
const port = Number(process.env.PORT || 4173);
const host = process.env.HOST || "127.0.0.1";
const exportKey = process.env.EXPORT_KEY || "";

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".wav": "audio/wav",
  ".png": "image/png",
  ".svg": "image/svg+xml"
};

async function main() {
  await fsp.mkdir(dataRoot, { recursive: true });
  const server = http.createServer((request, response) => {
    route(request, response).catch((error) => {
      console.error(error);
      sendJson(response, 500, { error: "Server error." });
    });
  });
  server.listen(port, host, () => {
    console.log(`2IFC study available at http://${host}:${port}`);
  });
}

async function route(request, response) {
  const url = new URL(request.url, `http://${request.headers.host || "localhost"}`);
  applySecurityHeaders(response);

  if (request.method === "GET" && url.pathname === "/api/health") {
    return sendJson(response, 200, { ok: true, study: "fisher-rao-2ifc" });
  }
  if (request.method === "POST" && url.pathname === "/api/session/start") {
    return startSession(request, response);
  }
  if (request.method === "POST" && url.pathname === "/api/response") {
    return storeResponse(request, response);
  }
  if (request.method === "POST" && url.pathname === "/api/session/complete") {
    return completeSession(request, response);
  }
  if (request.method === "POST" && url.pathname === "/api/session/pause") {
    return pauseSession(request, response);
  }
  if (request.method === "GET" && url.pathname === "/api/export.csv") {
    return exportResponses(url, response);
  }
  if (request.method === "GET" || request.method === "HEAD") {
    return servePublicFile(url.pathname, response, request.method === "HEAD");
  }
  sendJson(response, 404, { error: "Not found." });
}

async function startSession(request, response) {
  const body = await readJsonBody(request);
  const enteredParticipantCode = sanitiseCode(body.participantCode);
  if (!enteredParticipantCode || !body.consentConfirmed || !body.headphonesConfirmed) {
    return sendJson(response, 400, {
      error: "A participant code, consent confirmation and headphone confirmation are required."
    });
  }

  const participantCode = await resolveParticipantCode(enteredParticipantCode);
  const studyId = cleanText(body.studyId, 80);
  const manifestVersion = cleanText(body.manifestVersion, 80);
  const sessionId = `${new Date().toISOString().replace(/[:.]/g, "-")}_${crypto.randomBytes(6).toString("hex")}`;
  const seed = crypto.randomBytes(4).readUInt32LE(0);
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
    userAgent: cleanText(request.headers["user-agent"] || "", 300),
    previousProgress: await getParticipantProgress(participantCode, studyId, manifestVersion)
  };
  await writeJson(path.join(dataRoot, `session_${sessionId}.json`), session);
  sendJson(response, 201, session);
}

async function storeResponse(request, response) {
  const body = await readJsonBody(request);
  const sessionId = sanitiseSessionId(body.sessionId);
  const trialId = cleanText(body.trialId, 120);
  if (!sessionId || !trialId || !Number.isFinite(body.responseInterval)) {
    return sendJson(response, 400, { error: "Invalid trial response." });
  }
  const sessionKnown = await sessionExists(sessionId);
  const responseId = `${sessionId}:${trialId}`;
  if (await hasStoredResponse(responseId)) {
    return sendJson(response, 200, { stored: true, duplicate: true });
  }

  const row = {
    responseId,
    sessionId,
    sessionKnown,
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
  await fsp.appendFile(responseFile, `${JSON.stringify(row)}\n`, "utf8");
  sendJson(response, 201, { stored: true });
}

async function hasStoredResponse(responseId) {
  try {
    const lines = (await fsp.readFile(responseFile, "utf8"))
      .split(/\r?\n/)
      .filter(Boolean);
    return lines.some((line) => JSON.parse(line).responseId === responseId);
  } catch (error) {
    if (error.code === "ENOENT") {
      return false;
    }
    throw error;
  }
}

async function completeSession(request, response) {
  const body = await readJsonBody(request);
  const sessionId = sanitiseSessionId(body.sessionId);
  if (!sessionId) {
    return sendJson(response, 400, { error: "Invalid session." });
  }
  await requireSession(sessionId);
  const row = {
    sessionId,
    participantCode: sanitiseCode(body.participantCode),
    assignedVirtualHrtfSubjectId: finiteOrNull(body.assignedVirtualHrtfSubjectId),
    completedAt: new Date().toISOString(),
    completedTrialCount: finiteOrNull(body.completedTrialCount)
  };
  await fsp.appendFile(completionFile, `${JSON.stringify(row)}\n`, "utf8");
  sendJson(response, 201, { completed: true, completionCode: sessionId.slice(-12) });
}

async function pauseSession(request, response) {
  const body = await readJsonBody(request);
  const sessionId = sanitiseSessionId(body.sessionId);
  if (!sessionId) {
    return sendJson(response, 400, { error: "Invalid session." });
  }
  await requireSession(sessionId);
  const row = {
    sessionId,
    participantCode: sanitiseCode(body.participantCode),
    assignedVirtualHrtfSubjectId: finiteOrNull(body.assignedVirtualHrtfSubjectId),
    pausedAt: new Date().toISOString(),
    completedTrialCount: finiteOrNull(body.completedTrialCount)
  };
  await fsp.appendFile(pauseFile, `${JSON.stringify(row)}\n`, "utf8");
  sendJson(response, 201, {
    paused: true,
    resumeCode: row.participantCode,
    resumeInstruction: "Resume by entering the same participant code used at the start."
  });
}

async function exportResponses(url, response) {
  if (exportKey && url.searchParams.get("key") !== exportKey) {
    return sendJson(response, 403, { error: "Export key required." });
  }
  let records = [];
  try {
    const lines = (await fsp.readFile(responseFile, "utf8")).trim().split(/\r?\n/).filter(Boolean);
    records = lines.map((line) => JSON.parse(line));
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  const csv = toCsv(records);
  response.writeHead(200, {
    "Content-Type": "text/csv; charset=utf-8",
    "Content-Disposition": "attachment; filename=\"two_ifc_responses.csv\""
  });
  response.end(csv);
}

async function getParticipantProgress(participantCode, studyId, manifestVersion) {
  const records = await readNdjson(responseFile);
  const matching = records.filter((record) =>
    sanitiseCode(record.participantCode) === participantCode &&
    cleanText(record.studyId, 80) === studyId &&
    cleanText(record.manifestVersion, 80) === manifestVersion);

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

async function resolveParticipantCode(enteredCode) {
  const exactProgressRecords = (await readNdjson(responseFile))
    .filter((record) => sanitiseCode(record.participantCode) === enteredCode);
  if (exactProgressRecords.length > 0) {
    return enteredCode;
  }

  const pauseRecords = await readNdjson(pauseFile);
  for (let index = pauseRecords.length - 1; index >= 0; index -= 1) {
    const record = pauseRecords[index];
    if (sanitiseSessionId(record.sessionId).endsWith(enteredCode) ||
        sanitiseCode(record.participantCode) === enteredCode) {
      const participantCode = sanitiseCode(record.participantCode);
      if (participantCode) {
        return participantCode;
      }
    }
  }

  const sessionFiles = (await listSessionFiles()).reverse();
  for (const fileName of sessionFiles) {
    const sessionId = fileName.replace(/^session_/, "").replace(/\.json$/, "");
    if (!sessionId.endsWith(enteredCode)) {
      continue;
    }
    try {
      const session = JSON.parse(await fsp.readFile(path.join(dataRoot, fileName), "utf8"));
      const participantCode = sanitiseCode(session.participantCode);
      if (participantCode) {
        return participantCode;
      }
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }
    }
  }

  return enteredCode;
}

async function listSessionFiles() {
  try {
    return (await fsp.readdir(dataRoot))
      .filter((fileName) => /^session_.*\.json$/.test(fileName))
      .sort();
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
}

async function readNdjson(filePath) {
  try {
    const text = await fsp.readFile(filePath, "utf8");
    return text
      .split(/\r?\n/)
      .filter(Boolean)
      .map((line) => JSON.parse(line));
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
}

async function servePublicFile(pathname, response, headersOnly = false) {
  const requestPath = pathname === "/" ? "/index.html" : pathname;
  const resolved = path.resolve(publicRoot, `.${decodeURIComponent(requestPath)}`);
  if (!resolved.startsWith(publicRoot + path.sep) && resolved !== path.join(publicRoot, "index.html")) {
    return sendJson(response, 403, { error: "Forbidden." });
  }
  try {
    const contents = await fsp.readFile(resolved);
    const extension = path.extname(resolved).toLowerCase();
    response.writeHead(200, { "Content-Type": mimeTypes[extension] || "application/octet-stream" });
    response.end(headersOnly ? undefined : contents);
  } catch (error) {
    if (error.code === "ENOENT") {
      return sendJson(response, 404, { error: "Not found." });
    }
    throw error;
  }
}

function applySecurityHeaders(response) {
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("Content-Security-Policy",
    "default-src 'self'; script-src 'self'; style-src 'self'; media-src 'self'; connect-src 'self'");
}

async function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let raw = "";
    request.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 1e6) {
        request.destroy();
        reject(new Error("Request body is too large."));
      }
    });
    request.on("end", () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch (error) {
        reject(new Error("Malformed JSON request body."));
      }
    });
    request.on("error", reject);
  });
}

async function requireSession(sessionId) {
  await fsp.access(path.join(dataRoot, `session_${sessionId}.json`), fs.constants.F_OK);
}

async function sessionExists(sessionId) {
  try {
    await requireSession(sessionId);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") {
      return false;
    }
    throw error;
  }
}

function sendJson(response, status, payload) {
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(payload));
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

async function writeJson(filePath, value) {
  await fsp.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
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

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
