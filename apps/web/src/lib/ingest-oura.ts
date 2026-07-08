import JSZip from "jszip";
import { db } from "./db";
import type { IngestResult } from "./ingest";

function parseCSV(text: string, delimiter = ";"): Record<string, string>[] {
  const lines = text.trim().split("\n");
  if (lines.length < 2) return [];
  const headers = lines[0].split(delimiter).map((h) => h.trim().replace(/^"|"$/g, ""));
  return lines.slice(1).map((line) => {
    const vals = line.split(delimiter).map((v) => v.trim().replace(/^"|"$/g, ""));
    const row: Record<string, string> = {};
    headers.forEach((h, i) => (row[h] = vals[i] ?? ""));
    return row;
  });
}

function toEpoch(dateStr: string): number {
  const d = new Date(dateStr);
  return isNaN(d.getTime()) ? 0 : d.getTime() / 1000;
}

async function fileHash(content: ArrayBuffer): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", content);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function ingestOuraZip(file: File): Promise<IngestResult> {
  const buf = await file.arrayBuffer();
  const hash = await fileHash(buf);

  const existing = await db.imports.where("hash").equals(hash).first();
  if (existing) {
    return { inserted: 0, skipped: 0, source: "oura", error: "This file has already been imported." };
  }

  let zip: JSZip;
  try {
    zip = await JSZip.loadAsync(buf);
  } catch {
    return { inserted: 0, skipped: 0, source: "oura", error: "Invalid ZIP file." };
  }

  let inserted = 0;
  let skipped = 0;

  for (const [name, entry] of Object.entries(zip.files)) {
    if (entry.dir || !name.endsWith(".csv")) continue;
    const text = await entry.async("text");
    const rows = parseCSV(text);
    if (rows.length === 0) continue;

    const lowerName = name.toLowerCase();

    if (lowerName.includes("heart_rate") || lowerName.includes("heartrate")) {
      for (const row of rows) {
        const ts = toEpoch(row.datetime || row.timestamp || row.date || "");
        const bpm = parseFloat(row.bpm || row.heart_rate || "0");
        if (ts === 0 || bpm === 0) continue;
        const ex = await db.heartRate.where("timestamp").equals(ts).first();
        if (ex) { skipped++; continue; }
        await db.heartRate.add({ timestamp: ts, bpm, ibiMs: null });
        inserted++;
      }
    }

    if (lowerName.includes("daily_sleep") || lowerName.includes("dailysleep")) {
      for (const row of rows) {
        const date = row.date || row.summary_date || "";
        if (!date) continue;
        const score = parseInt(row.score || row.score_total || "0", 10);
        const existing = await db.dailySummary.get(date);
        await db.dailySummary.put({
          date,
          totalSteps: existing?.totalSteps ?? 0,
          avgHr: parseFloat(row.hr_average || row.hr_avg || "0") || existing?.avgHr || 0,
          minHr: parseFloat(row.hr_lowest || row.hr_min || "0") || existing?.minHr || 0,
          avgHrv: parseFloat(row.rmssd || row.average_hrv || "0") || existing?.avgHrv || 0,
          avgSpo2: parseFloat(row.average_breath_variation || "0") || existing?.avgSpo2 || 0,
          avgTemp: existing?.avgTemp ?? 0,
          sleepScore: score || existing?.sleepScore || 0,
          readinessScore: existing?.readinessScore ?? 0,
          activityScore: existing?.activityScore ?? 0,
        });
        inserted++;
      }
    }

    if (lowerName.includes("daily_activity") || lowerName.includes("dailyactivity")) {
      for (const row of rows) {
        const date = row.date || row.summary_date || "";
        if (!date) continue;
        const existing = await db.dailySummary.get(date);
        await db.dailySummary.put({
          date,
          totalSteps: parseInt(row.steps || "0", 10) || existing?.totalSteps || 0,
          avgHr: existing?.avgHr ?? 0,
          minHr: existing?.minHr ?? 0,
          avgHrv: existing?.avgHrv ?? 0,
          avgSpo2: existing?.avgSpo2 ?? 0,
          avgTemp: existing?.avgTemp ?? 0,
          sleepScore: existing?.sleepScore ?? 0,
          readinessScore: existing?.readinessScore ?? 0,
          activityScore: parseInt(row.score || "0", 10) || existing?.activityScore || 0,
        });
        inserted++;
      }
    }

    if (lowerName.includes("daily_readiness") || lowerName.includes("dailyreadiness")) {
      for (const row of rows) {
        const date = row.date || row.summary_date || "";
        if (!date) continue;
        const existing = await db.dailySummary.get(date);
        await db.dailySummary.put({
          date,
          totalSteps: existing?.totalSteps ?? 0,
          avgHr: existing?.avgHr ?? 0,
          minHr: existing?.minHr ?? 0,
          avgHrv: existing?.avgHrv ?? 0,
          avgSpo2: existing?.avgSpo2 ?? 0,
          avgTemp: parseFloat(row.score_temperature || "0") || existing?.avgTemp || 0,
          sleepScore: existing?.sleepScore ?? 0,
          readinessScore: parseInt(row.score || "0", 10) || existing?.readinessScore || 0,
          activityScore: existing?.activityScore ?? 0,
        });
        inserted++;
      }
    }

    if (lowerName.includes("daily_spo2") || lowerName.includes("dailyspo2")) {
      for (const row of rows) {
        const ts = toEpoch(row.date || row.timestamp || "");
        const pct = parseFloat(row.spo2_percentage || row.average || row.spo2 || "0");
        if (ts === 0 || pct === 0) continue;
        const ex = await db.spo2.where("timestamp").equals(ts).first();
        if (ex) { skipped++; continue; }
        await db.spo2.add({ timestamp: ts, percent: Math.round(pct) });
        inserted++;
      }
    }

    if (lowerName.includes("temperature") && !lowerName.includes("trend")) {
      for (const row of rows) {
        const ts = toEpoch(row.date || row.timestamp || "");
        const celsius = parseFloat(row.temperature_delta || row.temperature_deviation || row.celsius || "0");
        if (ts === 0) continue;
        const ex = await db.temperature.where("timestamp").equals(ts).first();
        if (ex) { skipped++; continue; }
        await db.temperature.add({ timestamp: ts, celsius });
        inserted++;
      }
    }
  }

  await db.imports.add({
    filename: file.name,
    source: "oura",
    importedAt: new Date().toISOString(),
    recordCount: inserted,
    hash,
  });

  await db.imports.add({
    filename: file.name,
    source: "oura",
    importedAt: new Date().toISOString(),
    recordCount: inserted,
    hash,
  });

  const { syncAfterImport } = await import("./sync");
  syncAfterImport();

  return { inserted, skipped, source: "oura" };
}
