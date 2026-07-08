/**
 * Cloudflare Worker — R2 blob storage with Supabase JWT auth.
 * Structured health data stays in Supabase Postgres.
 */

import { extractBearer, verifyJwt } from "./jwt";

export interface Env {
  EXPORTS: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_JWT_SECRET: string;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ status: "ok", service: "librering-api" });
    }

    try {
      // Public object download (short-lived URLs point here; auth checked via query token)
      if (request.method === "GET" && url.pathname.startsWith("/v1/storage/object/")) {
        return handleGetObject(request, env, url);
      }

      // Direct upload PUT (upload_url from presign endpoint)
      if (request.method === "PUT" && url.pathname.startsWith("/v1/storage/upload/")) {
        return handlePutObject(request, env, url);
      }

      if (request.method !== "POST") {
        return json({ error: "method not allowed" }, 405);
      }

      const token = extractBearer(request);
      if (!token) return json({ error: "missing bearer token" }, 401);

      const user = await verifyJwt(token, env.SUPABASE_JWT_SECRET);
      if (!user?.sub) return json({ error: "invalid token" }, 401);

      if (url.pathname === "/v1/storage/upload-url") {
        return handleUploadUrl(request, env, user.sub, url.origin);
      }
      if (url.pathname === "/v1/storage/download-url") {
        return handleDownloadUrl(request, env, user.sub, url.origin, token);
      }

      return json({ error: "not found" }, 404);
    } catch (err) {
      return json({ error: String(err) }, 500);
    }
  },
};

async function handleUploadUrl(
  request: Request,
  env: Env,
  userId: string,
  origin: string
) {
  const body = (await request.json()) as { filename?: string; content_type?: string };
  const filename = sanitizeFilename(body.filename ?? "export.bin");
  const objectKey = `${userId}/${Date.now()}-${filename}`;
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();

  const uploadUrl = `${origin}/v1/storage/upload/${encodeURIComponent(objectKey)}`;

  await env.EXPORTS.put(`${objectKey}.meta`, JSON.stringify({
    content_type: body.content_type ?? "application/octet-stream",
    created_at: new Date().toISOString(),
  }));

  return json({
    object_key: objectKey,
    upload_url: uploadUrl,
    expires_at: expiresAt,
    method: "PUT",
    headers: { "Content-Type": body.content_type ?? "application/octet-stream" },
  });
}

async function handlePutObject(request: Request, env: Env, url: URL) {
  const token = extractBearer(request);
  if (!token) return json({ error: "missing bearer token" }, 401);

  const user = await verifyJwt(token, env.SUPABASE_JWT_SECRET);
  if (!user?.sub) return json({ error: "invalid token" }, 401);

  const prefix = "/v1/storage/upload/";
  const objectKey = decodeURIComponent(url.pathname.slice(prefix.length));
  if (!objectKey.startsWith(`${user.sub}/`)) {
    return json({ error: "forbidden" }, 403);
  }

  const contentType = request.headers.get("Content-Type") ?? "application/octet-stream";
  await env.EXPORTS.put(objectKey, request.body, {
    httpMetadata: { contentType },
  });

  return json({ object_key: objectKey, size: request.headers.get("Content-Length") });
}

async function handleDownloadUrl(
  request: Request,
  env: Env,
  userId: string,
  origin: string,
  token: string
) {
  const body = (await request.json()) as { object_key: string };
  if (!body.object_key?.startsWith(`${userId}/`)) {
    return json({ error: "forbidden" }, 403);
  }

  const obj = await env.EXPORTS.head(body.object_key);
  if (!obj) return json({ error: "not found" }, 404);

  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
  const downloadUrl = `${origin}/v1/storage/object/${encodeURIComponent(body.object_key)}?token=${encodeURIComponent(token)}`;

  return json({
    object_key: body.object_key,
    download_url: downloadUrl,
    expires_at: expiresAt,
  });
}

async function handleGetObject(request: Request, env: Env, url: URL) {
  const prefix = "/v1/storage/object/";
  const objectKey = decodeURIComponent(url.pathname.slice(prefix.length));
  const token = url.searchParams.get("token") ?? extractBearer(request);

  if (!token) return json({ error: "missing token" }, 401);

  const user = await verifyJwt(token, env.SUPABASE_JWT_SECRET);
  if (!user?.sub) return json({ error: "invalid token" }, 401);
  if (!objectKey.startsWith(`${user.sub}/`)) {
    return json({ error: "forbidden" }, 403);
  }

  const obj = await env.EXPORTS.get(objectKey);
  if (!obj) return json({ error: "not found" }, 404);

  const headers = new Headers(CORS_HEADERS);
  obj.writeHttpMetadata(headers);
  headers.set("Cache-Control", "private, max-age=900");

  return new Response(obj.body, { headers });
}

function sanitizeFilename(name: string): string {
  return name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 128);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}
