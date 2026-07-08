#!/usr/bin/env node
/** Smoke-test Supabase connectivity and migrations (no secrets printed). */

import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

const envPath = resolve(import.meta.dirname, "../apps/web/.env.local");
if (!existsSync(envPath)) {
  console.error("Missing apps/web/.env.local — run: pnpm wire:env");
  process.exit(1);
}

const env = Object.fromEntries(
  readFileSync(envPath, "utf8")
    .split("\n")
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => {
      const i = l.indexOf("=");
      return [l.slice(0, i), l.slice(i + 1)];
    })
);

const url = env.NEXT_PUBLIC_SUPABASE_URL;
const key = env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

const health = await fetch(`${url}/auth/v1/health`, { headers: { apikey: key } });
const healthJson = await health.json();
console.log(`Auth health: ${health.status} (${healthJson.name ?? "ok"})`);

if (!health.ok) {
  console.error("❌ Cannot reach Supabase — check URL and anon key");
  process.exit(1);
}

const rpc = await fetch(`${url}/rest/v1/rpc/push_sync_batch`, {
  method: "POST",
  headers: {
    apikey: key,
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ p_device_id: null, p_cursor: "0", p_batches: [] }),
});

if (rpc.status === 404) {
  console.error("❌ push_sync_batch RPC not found");
  console.error("   Run migrations in Supabase SQL Editor:");
  console.error("   1. backend/supabase/migrations/001_initial.sql");
  console.error("   2. backend/supabase/migrations/002_sync_rpc_full.sql");
  process.exit(1);
}

console.log(`push_sync_batch RPC: ${rpc.status} (401/400 expected without user session)`);
console.log("✅ Supabase connected and migrations appear applied");
