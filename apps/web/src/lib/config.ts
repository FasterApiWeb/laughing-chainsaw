import type { LibreRingConfig } from "@librering/sdk";

export function getLibreRingConfig(): LibreRingConfig | null {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) return null;

  return {
    supabaseUrl,
    supabaseAnonKey,
    workerUrl: process.env.NEXT_PUBLIC_WORKER_URL,
  };
}

export function isCloudEnabled(): boolean {
  return getLibreRingConfig() !== null;
}
