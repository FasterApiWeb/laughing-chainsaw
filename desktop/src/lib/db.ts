import Dexie, { type EntityTable } from "dexie";

export interface HeartRateRecord {
  id?: number;
  timestamp: number; // Unix epoch seconds
  bpm: number;
  ibiMs: number | null;
}

export interface SpO2Record {
  id?: number;
  timestamp: number;
  percent: number;
}

export interface TemperatureRecord {
  id?: number;
  timestamp: number;
  celsius: number;
}

export interface SleepPhaseRecord {
  id?: number;
  timestamp: number;
  phase: number; // 0=awake, 1=light, 2=deep, 3=REM
}

export interface StepRecord {
  id?: number;
  timestamp: number;
  count: number;
}

export interface BaselineRecord {
  metric: string;
  mean: number;
  deviation: number;
  sampleCount: number;
  lastUpdated: number;
}

export interface DailySummaryRecord {
  date: string; // YYYY-MM-DD
  totalSteps: number;
  avgHr: number;
  minHr: number;
  avgHrv: number;
  avgSpo2: number;
  avgTemp: number;
  sleepScore: number;
  readinessScore: number;
  activityScore: number;
}

export interface ImportRecord {
  id?: number;
  filename: string;
  source: string; // 'librering' | 'oura'
  importedAt: string; // ISO 8601
  recordCount: number;
  hash: string;
}

class LibreRingDB extends Dexie {
  heartRate!: EntityTable<HeartRateRecord, "id">;
  spo2!: EntityTable<SpO2Record, "id">;
  temperature!: EntityTable<TemperatureRecord, "id">;
  sleepPhase!: EntityTable<SleepPhaseRecord, "id">;
  steps!: EntityTable<StepRecord, "id">;
  baselines!: EntityTable<BaselineRecord, "metric">;
  dailySummary!: EntityTable<DailySummaryRecord, "date">;
  imports!: EntityTable<ImportRecord, "id">;

  constructor() {
    super("librering");
    this.version(1).stores({
      heartRate: "++id, timestamp",
      spo2: "++id, timestamp",
      temperature: "++id, timestamp",
      sleepPhase: "++id, timestamp",
      steps: "++id, timestamp",
      baselines: "metric",
      dailySummary: "date",
      imports: "++id, hash, importedAt",
    });
  }
}

export const db = new LibreRingDB();
