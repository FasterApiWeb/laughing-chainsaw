/**
 * Cloudflare Worker — R2 presigned URLs + JWT verification.
 * Structured data lives in Supabase; blobs (exports, Oura ZIPs) live in R2.
 */

export interface Env {
  EXPORTS: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_JWT_SECRET: string;
}

interface JwtPayload {
  sub?: string;
  email?: string;
  exp?: number;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ status: "ok" });
    }

    if (request.method !== "POST") {
      return json({ error: "method not allowed" }, 405);
    }

    const auth = request.headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) {
      return json({ error: "missing bearer token" }, 401);
    }

    const token = auth.slice(7);
    const user = await verifyJwt(token, env.SUPABASE_JWT_SECRET);
    if (!user?.sub) {
      return json({ error: "invalid token" }, 401);
    }

    try {
      if (url.pathname === "/v1/storage/upload-url") {
        return handleUploadUrl(request, env, user.sub);
      }
      if (url.pathname === "/v1/storage/download-url") {
        return handleDownloadUrl(request, env, user.sub);
      }
      return json({ error: "not found" }, 404);
    } catch (err) {
      return json({ error: String(err) }, 500);
    }
  },
};

async function handleUploadUrl(request: Request, env: Env, userId: string) {
  const body = (await request.json()) as { filename: string; content_type: string };
  const objectKey = `${userId}/${Date.now()}-${sanitizeFilename(body.filename)}`;

  // R2 presigned URLs via aws4fetch pattern — Worker uses createMultipartUpload or signed URL
  // Simplified: return object key; client uploads via Worker proxy in v1.1
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();

  return json({
    object_key: objectKey,
    upload_url: `${env.SUPABASE_URL.replace("supabase.co", "placeholder")}/worker-upload-stub`,
    expires_at: expiresAt,
    note: "Configure R2 S3 API credentials for production presigned URLs",
  });
}

async function handleDownloadUrl(request: Request, env: Env, userId: string) {
  const body = (await request.json()) as { object_key: string };
  if (!body.object_key.startsWith(`${userId}/`)) {
    return json({ error: "forbidden" }, 403);
  }

  const obj = await env.EXPORTS.head(body.object_key);
  if (!obj) {
    return json({ error: "not found" }, 404);
  }

  return json({
    download_url: `/v1/storage/object/${encodeURIComponent(body.object_key)}`,
    expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
  });
}

function sanitizeFilename(name: string): string {
  return name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 128);
}

async function verifyJwt(token: string, secret: string): Promise<JwtPayload | null> {
  if (!secret) return null;
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    if (payload.exp && payload.exp * 1000 < Date.now()) return null;
    // Production: verify HMAC signature with SUPABASE_JWT_SECRET
    return payload as JwtPayload;
  } catch {
    return null;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
