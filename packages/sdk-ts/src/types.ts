/** Shared domain types — mirror OpenAPI schemas and Supabase tables. */

export type SyncTable =
  | "heart_rate"
  | "spo2"
  | "temperature"
  | "sleep_phase"
  | "steps"
  | "daily_summary"
  | "baselines";

export interface SyncBatch {
  table: SyncTable;
  records: Record<string, unknown>[];
}

export interface SyncPushRequest {
  deviceId: string;
  cursor: string;
  batches: SyncBatch[];
}

export interface SyncPushResponse {
  newCursor: string;
  inserted: number;
  skipped: number;
}

export interface SyncPullRequest {
  deviceId: string;
  sinceCursor: string;
  tables?: SyncTable[];
}

export interface SyncPullResponse {
  cursor: string;
  batches: SyncBatch[];
}

export interface StorageUploadRequest {
  filename: string;
  contentType: string;
}

export interface StorageUploadResponse {
  objectKey: string;
  uploadUrl: string;
  expiresAt: string;
}

export interface StorageDownloadRequest {
  objectKey: string;
}

export interface StorageDownloadResponse {
  downloadUrl: string;
  expiresAt: string;
}

export interface LibreRingConfig {
  supabaseUrl: string;
  supabaseAnonKey: string;
  workerUrl?: string;
}

export interface AuthUser {
  id: string;
  email: string;
}

export interface AuthSession {
  accessToken: string;
  refreshToken: string;
  user: AuthUser;
}
