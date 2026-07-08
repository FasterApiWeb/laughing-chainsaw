import { db } from "./db";

interface LibreRingExport {
  source?: string;
  exported_at?: string;
  format_version?: number;
  range?: { start: string; end: string };
  heart_rate?: Array<{ timestamp: number; bpm: number; ibi_ms?: number }>;
  spo2?: Array<{ timestamp: number; percent: number }>;
  temperature?: Array<{ timestamp: number; celsius: number }>;
  sleep?: Array<{ timestamp: number; phase: number }>;
  steps?: Array<{ timestamp: number; count: number }>;
  daily_summary?: Array<{
    date: string;
    total_steps: number;
    avg_hr: number;
    min_hr: number;
    avg_hrv: number;
    avg_spo2: number;
    avg_temp: number;
    sleep_score: number;
    readiness_score: number;
    activity_score: number;
  }>;
  baselines?: Array<{
    metric: string;
    mean: number;
    deviation: number;
    sample_count: number;
    last_updated: number;
  }>;
}

export interface IngestResult {
  inserted: number;
  skipped: number;
  source: string;
  error?: string;
}

async function fileHash(content: string): Promise<string> {
  const buf = new TextEncoder().encode(content);
  const hash = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function ingestLibreRingJSON(content: string, filename: string): Promise<IngestResult> {
  let data: LibreRingExport;
  try {
    data = JSON.parse(content);
  } catch {
    return { inserted: 0, skipped: 0, source: "librering", error: "Invalid JSON" };
  }

  if (data.source && data.source !== "LibreRing") {
    return { inserted: 0, skipped: 0, source: "librering", error: `Unknown source: ${data.source}` };
  }

  const hash = await fileHash(content);
  const existing = await db.imports.where("hash").equals(hash).first();
  if (existing) {
    return { inserted: 0, skipped: 0, source: "librering", error: "This file has already been imported." };
  }

  let inserted = 0;
  let skipped = 0;

  if (data.heart_rate?.length) {
    for (const r of data.heart_rate) {
      const exists = await db.heartRate.where("timestamp").equals(r.timestamp).first();
      if (exists) { skipped++; continue; }
      await db.heartRate.add({ timestamp: r.timestamp, bpm: r.bpm, ibiMs: r.ibi_ms ?? null });
      inserted++;
    }
  }

  if (data.spo2?.length) {
    for (const r of data.spo2) {
      const exists = await db.spo2.where("timestamp").equals(r.timestamp).first();
      if (exists) { skipped++; continue; }
      await db.spo2.add({ timestamp: r.timestamp, percent: r.percent });
      inserted++;
    }
  }

  if (data.temperature?.length) {
    for (const r of data.temperature) {
      const exists = await db.temperature.where("timestamp").equals(r.timestamp).first();
      if (exists) { skipped++; continue; }
      await db.temperature.add({ timestamp: r.timestamp, celsius: r.celsius });
      inserted++;
    }
  }

  if (data.sleep?.length) {
    for (const r of data.sleep) {
      const exists = await db.sleepPhase.where("timestamp").equals(r.timestamp).first();
      if (exists) { skipped++; continue; }
      await db.sleepPhase.add({ timestamp: r.timestamp, phase: r.phase });
      inserted++;
    }
  }

  if (data.steps?.length) {
    for (const r of data.steps) {
      const exists = await db.steps.where("timestamp").equals(r.timestamp).first();
      if (exists) { skipped++; continue; }
      await db.steps.add({ timestamp: r.timestamp, count: r.count });
      inserted++;
    }
  }

  if (data.daily_summary?.length) {
    for (const r of data.daily_summary) {
      await db.dailySummary.put({
        date: r.date,
        totalSteps: r.total_steps,
        avgHr: r.avg_hr,
        minHr: r.min_hr,
        avgHrv: r.avg_hrv,
        avgSpo2: r.avg_spo2,
        avgTemp: r.avg_temp,
        sleepScore: r.sleep_score,
        readinessScore: r.readiness_score,
        activityScore: r.activity_score,
      });
      inserted++;
    }
  }

  if (data.baselines?.length) {
    for (const r of data.baselines) {
      await db.baselines.put({
        metric: r.metric,
        mean: r.mean,
        deviation: r.deviation,
        sampleCount: r.sample_count,
        lastUpdated: r.last_updated,
      });
      inserted++;
    }
  }

  await db.imports.add({
    filename,
    source: "librering",
    importedAt: new Date().toISOString(),
    recordCount: inserted,
    hash,
  });

  return { inserted, skipped, source: "librering" };
}
