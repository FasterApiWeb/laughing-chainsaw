export interface BaselineValue {
  mean: number;
  deviation: number;
  sampleCount: number;
  lastUpdated: number;
}

const ALPHA_UP = 0.05;
const ALPHA_DOWN = 0.15;
const MIN_SAMPLES = 3;
const WINDOW_DAYS = 14;

export function computeBaseline(currentValue: number, previous: BaselineValue | null): BaselineValue {
  if (!previous || previous.sampleCount < MIN_SAMPLES) {
    const count = (previous?.sampleCount ?? 0) + 1;
    const oldMean = previous?.mean ?? currentValue;
    const newMean = oldMean + (currentValue - oldMean) / count;
    const oldDev = previous?.deviation ?? 0;
    const newDev = oldDev + (Math.abs(currentValue - newMean) - oldDev) / count;
    return { mean: newMean, deviation: Math.max(newDev, 1.0), sampleCount: count, lastUpdated: Date.now() / 1000 };
  }

  const alpha = currentValue > previous.mean ? ALPHA_UP : ALPHA_DOWN;
  const newMean = previous.mean + alpha * (currentValue - previous.mean);
  const newDev = previous.deviation + alpha * (Math.abs(currentValue - newMean) - previous.deviation);

  return {
    mean: newMean,
    deviation: Math.max(newDev, 1.0),
    sampleCount: previous.sampleCount + 1,
    lastUpdated: Date.now() / 1000,
  };
}

export function deviationFromBaseline(value: number, baseline: BaselineValue): number {
  if (baseline.deviation <= 0) return 0;
  return (value - baseline.mean) / baseline.deviation;
}

export function computeFromHistory(values: number[]): BaselineValue | null {
  if (values.length === 0) return null;
  const window = values.slice(-WINDOW_DAYS);
  const sorted = [...window].sort((a, b) => a - b);
  const median = sorted[Math.floor(sorted.length / 2)];
  const mean = window.reduce((a, b) => a + b, 0) / window.length;
  const variance = window.reduce((sum, v) => sum + (v - mean) ** 2, 0) / window.length;
  return {
    mean: median,
    deviation: Math.max(Math.sqrt(variance), 1.0),
    sampleCount: window.length,
    lastUpdated: Date.now() / 1000,
  };
}
