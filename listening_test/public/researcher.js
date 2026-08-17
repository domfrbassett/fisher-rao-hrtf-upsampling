"use strict";

window.addEventListener("DOMContentLoaded", initialiseAudit);

async function initialiseAudit() {
  try {
    const config = await fetchJson("config/experiment.adaptive.json");
    const manifest = await fetchJson(config.manifest || "config/trials.adaptive.json");
    renderManifestSummary(config, manifest);
    await auditStudyManifest(manifest);
  } catch (error) {
    document.getElementById("design-summary").textContent =
      "The study manifest could not be loaded.";
    document.getElementById("manifest-status").textContent =
      "No stimulus bank is available yet.";
    console.error(error);
  }
}

function renderManifestSummary(config, manifest) {
  const blocks = manifest.blocks || [];
  const tracks = blocks.flatMap((block) => block.tracks || []);
  const methods = [...new Set(tracks.map((track) => track.method))].sort();
  const retentions = [...new Set(tracks.map((track) => track.retainedDirections))].sort((a, b) => a - b);
  const virtualSubjects = manifest.virtualHrtfSubjectIds || [];
  const levels = tracks.reduce((total, track) => total + (track.levels || []).length, 0);

  document.getElementById("design-summary").textContent =
    `${config.title || "Spatial Direction Discrimination"}: ${blocks.length} blocks, ${tracks.length} tracks, ` +
    `${levels} rendered separation levels, and ${virtualSubjects.length} representative ` +
    `SONICOM virtual identities.`;

  const cards = [
    ["Manifest", config.manifest || "config/trials.adaptive.json"],
    ["Version", manifest.manifestVersion || config.manifestVersion || "unknown"],
    ["Renderer", manifest.renderInterpolation || "StoredGridOnly"],
    ["Virtual identities", virtualSubjects.map(formatSubject).join(", ")]
  ];
  document.getElementById("design-cards").innerHTML = cards.map(([label, value]) =>
    `<div class="plan-card"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`
  ).join("");

  const rows = methods.map((method) => {
    const methodTracks = tracks.filter((track) => track.method === method);
    const role = methodTracks.some((track) => track.fieldType === "reference") ?
      "measured dense control" : "reconstruction";
    const methodRetentions = [...new Set(methodTracks.map((track) => track.retainedDirections))]
      .sort((a, b) => a - b)
      .map((n) => `N=${n}`)
      .join(", ");
    return { method, role, conditions: methodRetentions };
  });
  document.getElementById("method-table").innerHTML = rows.map((row) =>
    `<tr><td><code>${escapeHtml(row.method)}</code></td>` +
    `<td>${escapeHtml(row.role)}</td><td>${escapeHtml(row.conditions)}</td></tr>`
  ).join("");
}

async function auditStudyManifest(manifest) {
  const status = document.getElementById("manifest-status");
  const results = document.getElementById("manifest-results");
  const tracks = (manifest.blocks || []).flatMap((block) => block.tracks || []);
  const levels = tracks.flatMap((track) => track.levels || []);
  const urls = [...new Set(levels.flatMap((level) => [
    level.stimuli?.standard?.url,
    level.stimuli?.target?.url,
    level.stimuli?.targetOpposite?.url
  ]).filter(Boolean))];

  if (urls.length === 0) {
    status.textContent = "The study manifest is present, but it does not reference any WAV files.";
    status.className = "audit-note problem";
    return;
  }

  const availability = await Promise.all(urls.map(async (url) => ({
    url,
    ready: (await fetch(url, { method: "HEAD", cache: "no-store" })).ok
  })));
  const missing = availability.filter((item) => !item.ready);
  status.textContent = missing.length === 0 ?
    `Study manifest found: ${tracks.length} tracks, ${levels.length} levels and ${urls.length} WAV files are available.` :
    `Study manifest found, but ${missing.length} of ${urls.length} referenced WAV files are missing.`;
  status.className = `audit-note ${missing.length === 0 ? "ready" : "problem"}`;
  if (missing.length > 0) {
    results.innerHTML = `<p class="error">Missing files:</p><ul>${missing
      .map((item) => `<li><code>${escapeHtml(item.url)}</code></li>`).join("")}</ul>`;
  } else {
    results.innerHTML = "";
  }
}

async function fetchJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Unable to load ${url}`);
  }
  return response.json();
}

function formatSubject(subjectId) {
  return `P${String(subjectId).padStart(4, "0")}`;
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;"
  }[character]));
}
