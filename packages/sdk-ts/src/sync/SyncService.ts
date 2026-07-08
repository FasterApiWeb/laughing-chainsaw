import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  SyncBatch,
  SyncPullRequest,
  SyncPullResponse,
  SyncPushRequest,
  SyncPushResponse,
} from "../types.js";

/** Sync port — push/pull health data via Supabase RPC + tables. */
export interface SyncService {
  push(request: SyncPushRequest): Promise<SyncPushResponse>;
  pull(request: SyncPullRequest): Promise<SyncPullResponse>;
}

export class SupabaseSyncService implements SyncService {
  constructor(private readonly client: SupabaseClient) {}

  async push(request: SyncPushRequest): Promise<SyncPushResponse> {
    const { data, error } = await this.client.rpc("push_sync_batch", {
      p_device_id: request.deviceId,
      p_cursor: request.cursor,
      p_batches: request.batches.map(toRpcBatch),
    });

    if (error) throw new Error(error.message);

    return {
      newCursor: data?.new_cursor ?? request.cursor,
      inserted: data?.inserted ?? 0,
      skipped: data?.skipped ?? 0,
    };
  }

  async pull(request: SyncPullRequest): Promise<SyncPullResponse> {
    const { data, error } = await this.client.rpc("pull_sync_delta", {
      p_device_id: request.deviceId,
      p_since_cursor: request.sinceCursor,
      p_tables: request.tables ?? null,
    });

    if (error) throw new Error(error.message);

    const batches = (data?.batches ?? []) as SyncBatch[];
    return {
      cursor: data?.cursor ?? request.sinceCursor,
      batches,
    };
  }
}

function toRpcBatch(batch: SyncBatch) {
  return { table: batch.table, records: batch.records };
}

export function createSyncService(client: SupabaseClient): SyncService {
  return new SupabaseSyncService(client);
}
