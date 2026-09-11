"use strict";

const assert = require("node:assert/strict");
const adaptive = require("../public/adaptive.js");

const levels = [30, 20, 15, 10, 7, 5, 3.5, 2.5, 1.75, 1.25, 0.9, 0.6]
  .map((separationDeg) => ({ separationDeg }));
const rule = {
  targetPc: 0.76,
  thresholdMinDeg: 0.6,
  thresholdMaxDeg: 15,
  thresholdGridSize: 51,
  slopeValues: [1.5, 2, 3, 4, 6, 8],
  lapseValues: [0, 0.02, 0.05]
};

for (const slope of rule.slopeValues) {
  for (const lapse of rule.lapseValues) {
    const probability = adaptive.probabilityCorrect(
      2.5, 2.5, slope, lapse, rule.targetPc);
    assert.ok(Math.abs(probability - rule.targetPc) < 1e-12);
  }
}

const model = adaptive.create(levels, rule);
assert.equal(model.posterior.length,
  rule.thresholdGridSize * rule.slopeValues.length * rule.lapseValues.length);
assert.ok(adaptive.selectLevel(model) >= 0);

for (let trial = 0; trial < 40; trial += 1) {
  const levelIndex = adaptive.selectLevel(model);
  const summary = adaptive.update(model, levelIndex, trial % 4 !== 0);
  assert.ok(Number.isFinite(summary.thresholdEstimateDeg));
  assert.ok(summary.thresholdCiLowerDeg <= summary.thresholdEstimateDeg);
  assert.ok(summary.thresholdEstimateDeg <= summary.thresholdCiUpperDeg);
}

const posteriorSum = Array.from(model.posterior)
  .reduce((total, probability) => total + probability, 0);
assert.ok(Math.abs(posteriorSum - 1) < 1e-10);

console.log("Adaptive psychometric tests passed.");
