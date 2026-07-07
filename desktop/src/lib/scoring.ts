export interface SleepScore {
  total: number;
  durationScore: number;
  efficiencyScore: number;
  deepScore: number;
  remScore: number;
  latencyScore: number;
  label: string;
}

function clampedScore(value: number, optimal: number, min: number, max: number): number {
  if (value >= optimal) {
    const excess = value - optimal;
    const range = max - optimal;
    return range > 0 ? Math.max(0, 100 - Math.floor((excess / range) * 30)) : 100;
  } else {
    const deficit = optimal - value;
    const range = optimal - min;
    return range > 0 ? Math.max(0, 100 - Math.floor((deficit / range) * 100)) : 0;
  }
}

function scoreLabel(total: number): string {
  if (total >= 85) return "Optimal";
  if (total >= 70) return "Good";
  if (total >= 50) return "Fair";
  return "Poor";
}

export function computeSleepScore(
  totalSleepMinutes: number,
  timeInBedMinutes: number,
  deepPercent: number,
  remPercent: number,
  latencyMinutes: number
): SleepScore {
  const durationScore = clampedScore(totalSleepMinutes, 480, 300, 600);
  const efficiency = timeInBedMinutes > 0 ? (totalSleepMinutes / timeInBedMinutes) * 100 : 0;
  const efficiencyScore = Math.min(100, Math.max(0, Math.floor(efficiency)));
  const deepScore = clampedScore(deepPercent, 20, 5, 35);
  const remScore = clampedScore(remPercent, 22, 10, 35);
  const latencyScore = Math.max(0, Math.min(100, 100 - Math.floor(Math.max(0, latencyMinutes - 5) * 3)));

  const total = Math.min(
    100,
    Math.max(
      0,
      Math.floor(
        durationScore * 0.3 +
        efficiencyScore * 0.25 +
        deepScore * 0.2 +
        remScore * 0.15 +
        latencyScore * 0.1
      )
    )
  );

  return { total, durationScore, efficiencyScore, deepScore, remScore, latencyScore, label: scoreLabel(total) };
}

export interface ReadinessResult {
  total: number;
  hrvScore: number;
  restingHRScore: number;
  temperatureScore: number;
  sleepScore: number;
  recoveryScore: number;
  label: string;
}

function readinessLabel(total: number): string {
  if (total >= 85) return "Optimal";
  if (total >= 70) return "Good";
  if (total >= 50) return "Fair";
  return "Pay attention";
}

export function computeReadinessScore(
  currentHRV: number,
  baselineHRV: number,
  currentRestingHR: number,
  baselineRestingHR: number,
  tempDeviation: number,
  sleepScoreVal: number,
  recoveryIndex: number
): ReadinessResult {
  const hrvRatio = baselineHRV > 0 ? currentHRV / baselineHRV : 1.0;
  const hrvScore = Math.min(100, Math.max(0, Math.floor(hrvRatio * 80)));
  const hrDiff = currentRestingHR - baselineRestingHR;
  const restingHRScore = Math.min(100, Math.max(0, 80 - Math.floor(hrDiff * 5)));
  const temperatureScore = Math.min(100, Math.max(0, 100 - Math.floor(Math.abs(tempDeviation) * 50)));
  const sleepScore = Math.min(100, Math.max(0, sleepScoreVal));
  const recoveryScore = Math.min(100, Math.max(0, Math.floor(recoveryIndex * 100)));

  const total = Math.min(
    100,
    Math.max(
      0,
      Math.floor(
        hrvScore * 0.35 +
        restingHRScore * 0.2 +
        temperatureScore * 0.15 +
        sleepScore * 0.2 +
        recoveryScore * 0.1
      )
    )
  );

  return { total, hrvScore, restingHRScore, temperatureScore, sleepScore, recoveryScore, label: readinessLabel(total) };
}

export interface ActivityResult {
  total: number;
  stepsScore: number;
  activeCaloriesScore: number;
  moveScore: number;
  label: string;
}

function piecewise(ratio: number, points: [number, number][]): number {
  const r = Math.max(0, ratio);
  for (let i = 1; i < points.length; i++) {
    if (r <= points[i][0]) {
      const [x0, y0] = points[i - 1];
      const [x1, y1] = points[i];
      const t = (r - x0) / (x1 - x0);
      return Math.floor(y0 + t * (y1 - y0));
    }
  }
  return Math.floor(points[points.length - 1][1]);
}

function activityLabel(total: number): string {
  if (total >= 85) return "Optimal";
  if (total >= 70) return "Good";
  if (total >= 50) return "Fair";
  return "Low";
}

export function computeActivityScore(
  totalSteps: number,
  stepGoal: number = 10000,
  activeCalories: number = 0,
  calorieGoal: number = 350,
  inactiveMinutes: number = 0
): ActivityResult {
  const stepsScore = piecewise(totalSteps / Math.max(1, stepGoal), [[0, 0], [0.5, 25], [1.0, 85], [1.5, 100]]);
  const activeCaloriesScore = piecewise(activeCalories / Math.max(1, calorieGoal), [[0, 0], [0.5, 25], [1.0, 85], [1.5, 100]]);
  const moveRatio = Math.max(0, 1.0 - inactiveMinutes / 480.0);
  const moveScore = piecewise(moveRatio, [[0, 0], [0.3, 40], [0.7, 80], [1.0, 100]]);

  const total = Math.min(
    100,
    Math.max(0, Math.floor(stepsScore * 0.4 + activeCaloriesScore * 0.35 + moveScore * 0.25))
  );

  return { total, stepsScore, activeCaloriesScore, moveScore, label: activityLabel(total) };
}

export function estimateCalories(steps: number, weightKg: number = 70): number {
  return steps * 0.04 * weightKg / 70.0;
}
