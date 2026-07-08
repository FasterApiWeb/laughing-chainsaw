import { createAuthService } from "./auth/SupabaseAuthService.js";
import { createSyncService } from "./sync/SyncService.js";
import { createStorageService } from "./storage/StorageService.js";
import type { LibreRingConfig } from "./types.js";

export type { AuthService } from "./auth/AuthService.js";
export type { SyncService } from "./sync/SyncService.js";
export type { StorageService } from "./storage/StorageService.js";
export * from "./types.js";

/** Facade — single entry point for web/mobile clients (Facade pattern). */
export class LibreRingClient {
  readonly auth: ReturnType<typeof createAuthService>;
  readonly sync: ReturnType<typeof createSyncService>;
  readonly storage: ReturnType<typeof createStorageService>;

  constructor(config: LibreRingConfig) {
    this.auth = createAuthService(config);
    this.sync = createSyncService(this.auth.supabase);
    this.storage = createStorageService(config);
  }
}

export function createLibreRingClient(config: LibreRingConfig): LibreRingClient {
  return new LibreRingClient(config);
}

export { createAuthService, createSyncService, createStorageService };
