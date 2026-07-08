import type { SyncBatch } from "@librering/sdk";
import { getClient } from "./client";
import { isCloudEnabled } from "./config";
import { db } from "./db";

const CURSOR_KEY = "librering_sync_cursor";
const DEVICE_KEY = "librering_device_id";

/** Push local Dexie data to Supabase (offline-first: local is source of truth). */
export async function pushLocalToCloud(): Promise<{ ok: boolean; error?: string }> {
  if (!isCloudEnabled()) return { ok: false, error: "Cloud sync not configured" };

  const client = getClient();
  if (!client) return { ok: false, error: "Client unavailable" };

  const session = await client.auth.getSession();
  if (!session) return { ok: false, error: "Not signed in" };

  const deviceId = await ensureDeviceId(client);
  const cursor = localStorage.getItem(CURSOR_KEY) ?? new Date().toISOString();
  const batches = await collectLocalBatches();

  if (batches.every((b) => b.records.length === 0)) {
    return { ok: true };
  }

  try {
    const result = await client.sync.push({ deviceId, cursor, batches });
    localStorage.setItem(CURSOR_KEY, result.newCursor);
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err) };
  }
}

async function ensureDeviceId(client: NonNullable<ReturnType<typeof getClient>>): Promise<string> {
  const cached = localStorage.getItem(DEVICE_KEY);
  if (cached) return cached;

  const { data, error } = await client.auth.supabase
    .from("devices")
    .insert({ name: "Web Dashboard" })
    .select("id")
    .single();

  if (error || !data?.id) throw new Error(error?.message ?? "Failed to register device");

  localStorage.setItem(DEVICE_KEY, data.id);
  return data.id;
}

async function collectLocalBatches(): Promise<SyncBatch[]> {
  const [hr, spo2, temp, sleep, steps, daily, baselines] = await Promise.all([
    db.heartRate.toArray(),
    db.spo2.toArray(),
    db.temperature.toArray(),
    db.sleepPhase.toArray(),
    db.steps.toArray(),
    db.dailySummary.toArray(),
    db.baselines.toArray(),
  ]);

  return [
    {
      table: "heart_rate",
      records: hr.map((r) => ({
        timestamp: r.timestamp,
        bpm: r.bpm,
        ibi_ms: r.ibiMs,
      })),
    },
    {
      table: "spo2",
      records: spo2.map((r) => ({ timestamp: r.timestamp, percent: r.percent })),
    },
    {
      table: "temperature",
      records: temp.map((r) => ({ timestamp: r.timestamp, celsius: r.celsius })),
    },
    {
      table: "sleep_phase",
      records: sleep.map((r) => ({ timestamp: r.timestamp, phase: r.phase })),
    },
    {
      table: "steps",
      records: steps.map((r) => ({ timestamp: r.timestamp, count: r.count })),
    },
    {
      table: "daily_summary",
      records: daily.map((r) => ({
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
    },
    {
      table: "baselines",
      records: baselines.map((r) => ({
        metric: r.metric,
        mean: r.mean,
        deviation: r.deviation,
        sample_count: r.sampleCount,
        last_updated: r.lastUpdated,
      })),
    },
  ];
}
