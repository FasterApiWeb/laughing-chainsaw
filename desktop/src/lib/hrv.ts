export function rmssd(intervals: number[]): number {
  if (intervals.length < 2) return 0;
  let sumSquared = 0;
  for (let i = 1; i < intervals.length; i++) {
    const diff = intervals[i] - intervals[i - 1];
    sumSquared += diff * diff;
  }
  return Math.sqrt(sumSquared / (intervals.length - 1));
}

export function sdnn(intervals: number[]): number {
  if (intervals.length < 2) return 0;
  const mean = intervals.reduce((a, b) => a + b, 0) / intervals.length;
  const variance = intervals.reduce((sum, v) => sum + (v - mean) ** 2, 0) / (intervals.length - 1);
  return Math.sqrt(variance);
}

export function pnn50(intervals: number[]): number {
  if (intervals.length < 2) return 0;
  let count = 0;
  for (let i = 1; i < intervals.length; i++) {
    if (Math.abs(intervals[i] - intervals[i - 1]) > 50) count++;
  }
  return (count / (intervals.length - 1)) * 100;
}
