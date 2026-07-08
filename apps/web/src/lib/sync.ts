import type { SyncBatch } from "@librering/sdk";
import { getClient } from "./client";
import { isCloudEnabled, isWorkerEnabled } from "./config";
import { db } from "./db";

const CURSOR_KEY = "librering_sync_cursor";
const DEVICE_KEY = "librering_device_id";

export interface SyncResult {
  ok: boolean;
  error?: string;
  inserted?: number;
  skipped?: number;
  pulled?: number;
}

/** Push local Dexie data to Supabase (offline-first: local is source of truth). */
export async function pushLocalToCloud(): Promise<SyncResult> {
  if (!isCloudEnabled()) return { ok: false, error: "Cloud sync not configured" };

  const client = getClient();
  if (!client) return { ok: false, error: "Client unavailable" };

  const session = await client.auth.getSession();
  if (!session) return { ok: false, error: "Not signed in" };

  let deviceId: string;
  try {
    deviceId = await ensureDeviceId(client, session.user.id);
  } catch (err) {
    return { ok: false, error: formatError(err) };
  }

  const cursor = localStorage.getItem(CURSOR_KEY) ?? new Date().toISOString();
  const batches = await collectLocalBatches();

  if (batches.every((b) => b.records.length === 0)) {
    return { ok: true, inserted: 0, skipped: 0 };
  }

  try {
    const result = await client.sync.push({ deviceId, cursor, batches });
    localStorage.setItem(CURSOR_KEY, result.newCursor);
    return { ok: true, inserted: result.inserted, skipped: result.skipped };
  } catch (err) {
    return { ok: false, error: formatError(err) };
  }
}

/** Pull remote delta and merge into IndexedDB. */
export async function pullCloudToLocal(): Promise<SyncResult> {
  if (!isCloudEnabled()) return { ok: false, error: "Cloud sync not configured" };

  const client = getClient();
  if (!client) return { ok: false, error: "Client unavailable" };

  const session = await client.auth.getSession();
  if (!session) return { ok: false, error: "Not signed in" };

  let deviceId: string;
  try {
    deviceId = await ensureDeviceId(client, session.user.id);
  } catch (err) {
    return { ok: false, error: formatError(err) };
  }

  const sinceCursor = localStorage.getItem(CURSOR_KEY) ?? "0";

  try {
    const result = await client.sync.pull({ deviceId, sinceCursor });
    let pulled = 0;

    for (const batch of result.batches) {
      pulled += await mergeBatch(batch);
    }

    localStorage.setItem(CURSOR_KEY, result.cursor);
    return { ok: true, pulled };
  } catch (err) {
    return { ok: false, error: formatError(err) };
  }
}

/** Push then pull — full two-way sync. */
export async function syncWithCloud(): Promise<SyncResult> {
  const pushResult = await pushLocalToCloud();
  if (!pushResult.ok) return pushResult;

  const pullResult = await pullCloudToLocal();
  if (!pullResult.ok) return pullResult;

  return {
    ok: true,
    inserted: pushResult.inserted,
    skipped: pushResult.skipped,
    pulled: pullResult.pulled,
  };
}

/** Upload JSON export blob to R2 via Worker (when configured). */
export async function uploadExportToCloud(
  json: string,
  filename: string
): Promise<{ ok: boolean; error?: string; objectKey?: string }> {
  if (!isWorkerEnabled()) return { ok: false, error: "Blob storage not configured" };

  const client = getClient();
  if (!client?.storage) return { ok: false, error: "Storage client unavailable" };

  const session = await client.auth.getSession();
  if (!session) return { ok: false, error: "Not signed in" };

  try {
    const presign = await client.storage.createUploadUrl(
      { filename, contentType: "application/json" },
      session.accessToken
    );

    const res = await fetch(presign.uploadUrl!, {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${session.accessToken}`,
        "Content-Type": "application/json",
      },
      body: json,
    });

    if (!res.ok) {
      return { ok: false, error: `Upload failed: ${await res.text()}` };
    }

    // Record metadata in Supabase
    await client.auth.supabase.from("storage_objects").insert({
      object_key: presign.objectKey,
      filename,
      content_type: "application/json",
      byte_size: new Blob([json]).size,
      user_id: session.user.id,
    });

    return { ok: true, objectKey: presign.objectKey as string };
  } catch (err) {
    return { ok: false, error: formatError(err) };
  }
}

/** Fire-and-forget sync after import — never blocks UI on failure. */
export function syncAfterImport(): void {
  if (!isCloudEnabled()) return;
  void syncWithCloud().catch(() => {
    /* shown on next manual sync */
  });
}

async function ensureDeviceId(
  client: NonNullable<ReturnType<typeof getClient>>,
  userId: string
): Promise<string> {
  const cached = localStorage.getItem(DEVICE_KEY);
  if (cached) {
    const { data } = await client.auth.supabase
      .from("devices")
      .select("id")
      .eq("id", cached)
      .eq("user_id", userId)
      .maybeSingle();
    if (data?.id) return data.id;
    localStorage.removeItem(DEVICE_KEY);
  }

  // Reuse existing web device if present
  const { data: existing } = await client.auth.supabase
    .from("devices")
    .select("id")
    .eq("user_id", userId)
    .eq("name", "Web Dashboard")
    .is("ble_mac", null)
    .maybeSingle();

  if (existing?.id) {
    localStorage.setItem(DEVICE_KEY, existing.id);
    return existing.id;
  }

  const { data, error } = await client.auth.supabase
    .from("devices")
    .insert({ name: "Web Dashboard", user_id: userId })
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
      records: hr.map((r) => ({ timestamp: r.timestamp, bpm: r.bpm, ibi_ms: r.ibiMs })),
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

async function mergeBatch(batch: SyncBatch): Promise<number> {
  let count = 0;

  switch (batch.table) {
    case "heart_rate":
      for (const r of batch.records) {
        const ts = r.timestamp as number;
        if (await db.heartRate.where("timestamp").equals(ts).first()) continue;
        await db.heartRate.add({
          timestamp: ts,
          bpm: r.bpm as number,
          ibiMs: (r.ibi_ms as number | null) ?? null,
        });
        count++;
      }
      break;
    case "spo2":
      for (const r of batch.records) {
        const ts = r.timestamp as number;
        if (await db.spo2.where("timestamp").equals(ts).first()) continue;
        await db.spo2.add({ timestamp: ts, percent: r.percent as number });
        count++;
      }
      break;
    case "temperature":
      for (const r of batch.records) {
        const ts = r.timestamp as number;
        if (await db.temperature.where("timestamp").equals(ts).first()) continue;
        await db.temperature.add({ timestamp: ts, celsius: r.celsius as number });
        count++;
      }
      break;
    case "sleep_phase":
      for (const r of batch.records) {
        const ts = r.timestamp as number;
        if (await db.sleepPhase.where("timestamp").equals(ts).first()) continue;
        await db.sleepPhase.add({ timestamp: ts, phase: r.phase as number });
        count++;
      }
      break;
    case "steps":
      for (const r of batch.records) {
        const ts = r.timestamp as number;
        if (await db.steps.where("timestamp").equals(ts).first()) continue;
        await db.steps.add({ timestamp: ts, count: r.count as number });
        count++;
      }
      break;
    case "daily_summary":
      for (const r of batch.records) {
        await db.dailySummary.put({
          date: r.date as string,
          totalSteps: (r.total_steps as number) ?? 0,
          avgHr: (r.avg_hr as number) ?? 0,
          minHr: (r.min_hr as number) ?? 0,
          avgHrv: (r.avg_hrv as number) ?? 0,
          avgSpo2: (r.avg_spo2 as number) ?? 0,
          avgTemp: (r.avg_temp as number) ?? 0,
          sleepScore: (r.sleep_score as number) ?? 0,
          readinessScore: (r.readiness_score as number) ?? 0,
          activityScore: (r.activity_score as number) ?? 0,
        });
        count++;
      }
      break;
    case "baselines":
      for (const r of batch.records) {
        await db.baselines.put({
          metric: r.metric as string,
          mean: r.mean as number,
          deviation: r.deviation as number,
          sampleCount: r.sample_count as number,
          lastUpdated: r.last_updated as number,
        });
        count++;
      }
      break;
  }

  return count;
}

function formatError(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}
