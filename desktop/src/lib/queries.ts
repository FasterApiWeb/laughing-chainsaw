import { db, type DailySummaryRecord, type HeartRateRecord, type SpO2Record } from "./db";

function daysAgoEpoch(days: number): number {
  return (Date.now() - days * 86400000) / 1000;
}

function toDateStr(epoch: number): string {
  return new Date(epoch * 1000).toISOString().slice(0, 10);
}

export async function getLatestMetrics() {
  const [hr, spo2, temp, steps] = await Promise.all([
    db.heartRate.orderBy("timestamp").last(),
    db.spo2.orderBy("timestamp").last(),
    db.temperature.orderBy("timestamp").last(),
    db.steps.orderBy("timestamp").last(),
  ]);
  return { hr, spo2, temp, steps };
}

export async function getLatestSummary(): Promise<DailySummaryRecord | undefined> {
  const all = await db.dailySummary.orderBy("date").reverse().limit(1).toArray();
  return all[0];
}

export async function getSummariesInRange(days: number): Promise<DailySummaryRecord[]> {
  const cutoff = toDateStr(daysAgoEpoch(days));
  return db.dailySummary.where("date").aboveOrEqual(cutoff).sortBy("date");
}

export async function getHeartRateInRange(fromEpoch: number, toEpoch: number): Promise<HeartRateRecord[]> {
  return db.heartRate.where("timestamp").between(fromEpoch, toEpoch, true, true).sortBy("timestamp");
}

export async function getSpO2InRange(fromEpoch: number, toEpoch: number): Promise<SpO2Record[]> {
  return db.spo2.where("timestamp").between(fromEpoch, toEpoch, true, true).sortBy("timestamp");
}

export async function getImportHistory() {
  return db.imports.orderBy("importedAt").reverse().toArray();
}

export async function getTotalRecordCount(): Promise<number> {
  const counts = await Promise.all([
    db.heartRate.count(),
    db.spo2.count(),
    db.temperature.count(),
    db.sleepPhase.count(),
    db.steps.count(),
  ]);
  return counts.reduce((a, b) => a + b, 0);
}

export async function exportAllData(): Promise<string> {
  const [heartRate, spo2, temperature, sleepPhase, steps, dailySummary, baselines] = await Promise.all([
    db.heartRate.toArray(),
    db.spo2.toArray(),
    db.temperature.toArray(),
    db.sleepPhase.toArray(),
    db.steps.toArray(),
    db.dailySummary.toArray(),
    db.baselines.toArray(),
  ]);

  return JSON.stringify(
    {
      source: "LibreRing Desktop",
      exported_at: new Date().toISOString(),
      format_version: 1,
      heart_rate: heartRate.map((r) => ({ timestamp: r.timestamp, bpm: r.bpm, ibi_ms: r.ibiMs })),
      spo2: spo2.map((r) => ({ timestamp: r.timestamp, percent: r.percent })),
      temperature: temperature.map((r) => ({ timestamp: r.timestamp, celsius: r.celsius })),
      sleep: sleepPhase.map((r) => ({ timestamp: r.timestamp, phase: r.phase })),
      steps: steps.map((r) => ({ timestamp: r.timestamp, count: r.count })),
      daily_summary: dailySummary.map((r) => ({
        date: r.date,
        total_steps: r.totalSteps,
        avg_hr: r.avgHr,
        min_hr: r.minHr,
        avg_hrv: r.avgHrv,
        avg_spo2: r.avgSpo2,
        avg_temp: r.avgTemp,
        sleep_score: r.sleepScore,
        readiness_score: r.readinessScore,
        activity_score: r.activityScore,
      })),
      baselines: baselines.map((r) => ({
        metric: r.metric,
        mean: r.mean,
        deviation: r.deviation,
        sample_count: r.sampleCount,
        last_updated: r.lastUpdated,
      })),
    },
    null,
    2
  );
}

export async function clearAllData(): Promise<void> {
  await Promise.all([
    db.heartRate.clear(),
    db.spo2.clear(),
    db.temperature.clear(),
    db.sleepPhase.clear(),
    db.steps.clear(),
    db.baselines.clear(),
    db.dailySummary.clear(),
    db.imports.clear(),
  ]);
}
