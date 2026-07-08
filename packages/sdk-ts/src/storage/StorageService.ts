import type {
  LibreRingConfig,
  StorageDownloadRequest,
  StorageDownloadResponse,
  StorageUploadRequest,
  StorageUploadResponse,
} from "../types.js";

/** Blob storage port — R2 via Cloudflare Worker (not Supabase Storage). */
export interface StorageService {
  createUploadUrl(
    request: StorageUploadRequest,
    accessToken: string
  ): Promise<StorageUploadResponse>;
  createDownloadUrl(
    request: StorageDownloadRequest,
    accessToken: string
  ): Promise<StorageDownloadResponse>;
}

export class WorkerStorageService implements StorageService {
  constructor(private readonly workerUrl: string) {}

  async createUploadUrl(
    request: StorageUploadRequest,
    accessToken: string
  ): Promise<StorageUploadResponse> {
    return this.post<StorageUploadResponse>(
      "/v1/storage/upload-url",
      request,
      accessToken
    );
  }

  async createDownloadUrl(
    request: StorageDownloadRequest,
    accessToken: string
  ): Promise<StorageDownloadResponse> {
    return this.post<StorageDownloadResponse>(
      "/v1/storage/download-url",
      request,
      accessToken
    );
  }

  private async post<T>(path: string, body: unknown, accessToken: string): Promise<T> {
    const res = await fetch(`${this.workerUrl}${path}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Storage API ${path} failed: ${text}`);
    }
    const json = await res.json();
    return mapStorageResponse(json) as T;
  }
}

function mapStorageResponse(raw: Record<string, unknown>) {
  return {
    objectKey: raw.object_key ?? raw.objectKey,
    uploadUrl: raw.upload_url ?? raw.uploadUrl,
    downloadUrl: raw.download_url ?? raw.downloadUrl,
    expiresAt: raw.expires_at ?? raw.expiresAt,
  };
}

export function createStorageService(config: LibreRingConfig): StorageService | null {
  if (!config.workerUrl) return null;
  return new WorkerStorageService(config.workerUrl);
}
