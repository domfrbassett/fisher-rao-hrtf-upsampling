"use strict";

const fs = require("node:fs");
const path = require("node:path");
const adaptive = require("../public/adaptive.js");

const repetitions = Number(process.argv[2] || 100);
const trialCount = Number(process.argv[3] || 30);
const outputPath = path.resolve(__dirname, "../audit/adaptive_simulation.json");
const levels = [30, 20, 15, 10, 7, 5, 3.5, 2.5, 1.75, 1.25, 0.9, 0.6]
  .map((separationDeg) => ({ separationDeg }));
const rule = {
  targetPc: 0.76,
  thresholdMinDeg: 0.6,
  thresholdMaxDeg: 15,
  thresholdGridSize: 51,
  slopeValues: [1.5, 2, 3, 4, 6, 8],
  lapseValues: [0, 0.02, 0.05],
  credibleMass: 0.95,
  maxTrials: trialCount
};
const scenarios = [
  { threshold: 0.75, slope: 3, lapse: 0.02 },
  { threshold: 1.25, slope: 3, lapse: 0.02 },
  { threshold: 2.5, slope: 3, lapse: 0.02 },
  { threshold: 5, slope: 3, lapse: 0.02 },
  { threshold: 10, slope: 3, lapse: 0.02 },
  { threshold: 14, slope: 3, lapse: 0.02 },
  { threshold: 2.5, slope: 1.5, lapse: 0.05 },
  { threshold: 2.5, slope: 8, lapse: 0 }
];

let randomState = 0x8f3a21c7;
function random() {
  randomState = (1664525 * randomState + 1013904223) >>> 0;
  return randomState / 0x100000000;
}

function quantile(values, probability) {
  const sorted = values.slice().sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1,
    Math.max(0, Math.round(probability * (sorted.length - 1))));
  return sorted[index];
}

function simulate(scenario) {
  const estimates = [];
  const logErrors = [];
  let covered = 0;
  for (let repetition = 0; repetition < repetitions; repetition += 1) {
    const model = adaptive.create(levels, rule);
    let summary;
    for (let trial = 0; trial < rule.maxTrials; trial += 1) {
      const levelIndex = adaptive.selectLevel(model);
      const separation = levels[levelIndex].separationDeg;
      const probability = adaptive.probabilityCorrect(
        separation, scenario.threshold, scenario.slope, scenario.lapse,
        rule.targetPc);
      summary = adaptive.update(model, levelIndex, random() < probability);
    }
    estimates.push(summary.thresholdEstimateDeg);
    logErrors.push(Math.log(summary.thresholdEstimateDeg / scenario.threshold));
    covered += Number(summary.thresholdCiLowerDeg <= scenario.threshold &&
      scenario.threshold <= summary.thresholdCiUpperDeg);
  }
  const meanLogError = logErrors.reduce((sum, value) => sum + value, 0) /
    logErrors.length;
  const meanSquaredLogError = logErrors.reduce(
    (sum, value) => sum + value * value, 0) / logErrors.length;
  return {
    ...scenario,
    repetitions,
    medianEstimateDeg: quantile(estimates, 0.5),
    estimateIntervalDeg: [quantile(estimates, 0.025), quantile(estimates, 0.975)],
    multiplicativeBias: Math.exp(meanLogError),
    logRmse: Math.sqrt(meanSquaredLogError),
    credibleIntervalCoverage: covered / repetitions
  };
}

const report = {
  generatedAt: new Date().toISOString(),
  rule,
  levelsDeg: levels.map((level) => level.separationDeg),
  scenarios: scenarios.map(simulate)
};
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.table(report.scenarios);
console.log(`Wrote ${outputPath}`);
