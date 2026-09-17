"use strict";

(function initialiseAdaptiveModule(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.HrtfAdaptive = api;
}(typeof globalThis !== "undefined" ? globalThis : this, function adaptiveFactory() {
  function create(levels, rule = {}) {
    const thresholdValues = logGrid(
      Number(rule.thresholdMinDeg ?? 0.6),
      Number(rule.thresholdMaxDeg ?? 15),
      Number(rule.thresholdGridSize ?? 51));
    const slopeValues = numericArray(rule.slopeValues, [1.5, 2, 3, 4, 6, 8]);
    const lapseValues = numericArray(rule.lapseValues, [0, 0.02, 0.05]);
    const targetPc = Number(rule.targetPc ?? 0.76);
    const levelValues = levels.map((level) => Number(level.separationDeg));
    const parameterCount = thresholdValues.length * slopeValues.length * lapseValues.length;
    const posterior = new Float64Array(parameterCount);
    posterior.fill(1 / parameterCount);
    const likelihoods = levelValues.map((separation) => {
      const values = new Float64Array(parameterCount);
      let index = 0;
      for (const threshold of thresholdValues) {
        for (const slope of slopeValues) {
          for (const lapse of lapseValues) {
            values[index] = probabilityCorrect(
              separation, threshold, slope, lapse, targetPc);
            index += 1;
          }
        }
      }
      return values;
    });
    return {
      targetPc,
      thresholdValues,
      slopeValues,
      lapseValues,
      posterior,
      likelihoods,
      trialNumber: 0
    };
  }

  function selectLevel(model) {
    let selected = 0;
    let minimumExpectedEntropy = Infinity;
    for (let levelIndex = 0; levelIndex < model.likelihoods.length; levelIndex += 1) {
      const likelihood = model.likelihoods[levelIndex];
      let probabilityOfCorrect = 0;
      for (let index = 0; index < model.posterior.length; index += 1) {
        probabilityOfCorrect += model.posterior[index] * likelihood[index];
      }
      const correctEntropy = conditionalEntropy(
        model.posterior, likelihood, probabilityOfCorrect, true);
      const incorrectEntropy = conditionalEntropy(
        model.posterior, likelihood, 1 - probabilityOfCorrect, false);
      const expectedEntropy = probabilityOfCorrect * correctEntropy +
        (1 - probabilityOfCorrect) * incorrectEntropy;
      if (expectedEntropy < minimumExpectedEntropy) {
        minimumExpectedEntropy = expectedEntropy;
        selected = levelIndex;
      }
    }
    return selected;
  }

  function update(model, levelIndex, correct) {
    const likelihood = model.likelihoods[levelIndex];
    let normalisingConstant = 0;
    for (let index = 0; index < model.posterior.length; index += 1) {
      model.posterior[index] *= correct ? likelihood[index] : 1 - likelihood[index];
      normalisingConstant += model.posterior[index];
    }
    if (!(normalisingConstant > 0)) {
      throw new Error("The adaptive posterior could not be normalised.");
    }
    for (let index = 0; index < model.posterior.length; index += 1) {
      model.posterior[index] /= normalisingConstant;
    }
    model.trialNumber += 1;
    return summary(model);
  }

  function summary(model) {
    const marginal = thresholdMarginal(model);
    let meanLogThreshold = 0;
    let posteriorEntropy = 0;
    for (let index = 0; index < marginal.length; index += 1) {
      meanLogThreshold += marginal[index] * Math.log(model.thresholdValues[index]);
    }
    for (const probability of model.posterior) {
      if (probability > 0) {
        posteriorEntropy -= probability * Math.log(probability);
      }
    }
    let logVariance = 0;
    for (let index = 0; index < marginal.length; index += 1) {
      const difference = Math.log(model.thresholdValues[index]) - meanLogThreshold;
      logVariance += marginal[index] * difference * difference;
    }
    return {
      thresholdEstimateDeg: Math.exp(meanLogThreshold),
      thresholdCiLowerDeg: weightedQuantile(
        model.thresholdValues, marginal, 0.025),
      thresholdCiUpperDeg: weightedQuantile(
        model.thresholdValues, marginal, 0.975),
      thresholdPosteriorLogSd: Math.sqrt(Math.max(0, logVariance)),
      adaptivePosteriorEntropy: posteriorEntropy
    };
  }

  function probabilityCorrect(separation, threshold, slope, lapse, targetPc) {
    const guessRate = 0.5;
    const availableRange = 1 - guessRate - lapse;
    const targetFraction = (targetPc - guessRate) / availableRange;
    if (!(separation > 0) || !(threshold > 0) || !(slope > 0) ||
        !(targetFraction > 0 && targetFraction < 1)) {
      throw new Error("Invalid psychometric-function parameter.");
    }
    const scale = -Math.log(1 - targetFraction);
    const detected = 1 - Math.exp(-scale * Math.pow(separation / threshold, slope));
    return guessRate + availableRange * detected;
  }

  function conditionalEntropy(posterior, likelihood, outcomeProbability, correct) {
    if (!(outcomeProbability > 0)) {
      return 0;
    }
    let entropy = 0;
    for (let index = 0; index < posterior.length; index += 1) {
      const conditional = posterior[index] *
        (correct ? likelihood[index] : 1 - likelihood[index]) / outcomeProbability;
      if (conditional > 0) {
        entropy -= conditional * Math.log(conditional);
      }
    }
    return entropy;
  }

  function thresholdMarginal(model) {
    const valuesPerThreshold = model.slopeValues.length * model.lapseValues.length;
    const marginal = new Float64Array(model.thresholdValues.length);
    for (let thresholdIndex = 0;
      thresholdIndex < model.thresholdValues.length; thresholdIndex += 1) {
      const offset = thresholdIndex * valuesPerThreshold;
      for (let innerIndex = 0; innerIndex < valuesPerThreshold; innerIndex += 1) {
        marginal[thresholdIndex] += model.posterior[offset + innerIndex];
      }
    }
    return marginal;
  }

  function weightedQuantile(values, weights, quantile) {
    let cumulative = 0;
    for (let index = 0; index < values.length; index += 1) {
      cumulative += weights[index];
      if (cumulative >= quantile) {
        return values[index];
      }
    }
    return values[values.length - 1];
  }

  function logGrid(minimum, maximum, count) {
    if (!(minimum > 0) || !(maximum > minimum) || count < 2) {
      throw new Error("Invalid adaptive threshold grid.");
    }
    const values = [];
    const logMinimum = Math.log(minimum);
    const step = (Math.log(maximum) - logMinimum) / (count - 1);
    for (let index = 0; index < count; index += 1) {
      values.push(Math.exp(logMinimum + index * step));
    }
    return values;
  }

  function numericArray(value, fallback) {
    const values = Array.isArray(value) ? value.map(Number).filter(Number.isFinite) : [];
    return values.length > 0 ? values : fallback.slice();
  }

  return { create, selectLevel, update, summary, probabilityCorrect };
}));
