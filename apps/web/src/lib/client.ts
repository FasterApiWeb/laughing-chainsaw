import { createLibreRingClient, type LibreRingClient } from "@librering/sdk";
import { getLibreRingConfig } from "./config";

let client: LibreRingClient | null = null;

export function getClient(): LibreRingClient | null {
  if (client) return client;
  const config = getLibreRingConfig();
  if (!config) return null;
  client = createLibreRingClient(config);
  return client;
}
