#!/usr/bin/env node
/**
 * Validate cloud env files exist and look configured (no secrets printed).
 * Usage: node scripts/check-cloud-env.mjs
 */

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");

function checkFile(label, relPath, requiredKeys) {
  const path = resolve(root, relPath);
  if (!existsSync(path)) {
    console.log(`⬜ ${label}: missing (${relPath})`);
    return false;
  }
  const content = readFileSync(path, "utf8");
  const missing = requiredKeys.filter((k) => {
    const m = content.match(new RegExp(`^${k}=(.+)$`, "m"));
    return !m || !m[1].trim() || m[1].includes("your-") || m[1].includes("YOUR_");
  });
  if (missing.length) {
    console.log(`🟡 ${label}: present but incomplete — set ${missing.join(", ")}`);
    return false;
  }
  console.log(`✅ ${label}: configured`);
  return true;
}

console.log("LibreRing cloud env check\n");

const webOk = checkFile("Web (.env.local)", "apps/web/.env.local", [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
]);

const workerOk = checkFile("Worker secrets (.dev.vars)", "backend/worker/.dev.vars", [
  "SUPABASE_JWT_SECRET",
]);

const supabaseOk = checkFile("Supabase (backend/.env)", "backend/supabase/.env", [
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
]);

console.log("");
if (webOk) {
  console.log("Next: pnpm dev:web → sign up → import → Settings → Sync Now");
} else {
  console.log("Next: cp apps/web/.env.example apps/web/.env.local and fill Supabase keys");
}
if (!workerOk) {
  console.log("R2 optional: wrangler secret put SUPABASE_JWT_SECRET && pnpm --filter @librering/worker deploy");
}

process.exit(webOk && supabaseOk ? 0 : 1);
