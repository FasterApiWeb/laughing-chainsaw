import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { AuthService } from "./AuthService.js";
import type { AuthSession, AuthUser, LibreRingConfig } from "../types.js";

function mapSession(session: {
  access_token: string;
  refresh_token: string;
  user: { id: string; email?: string };
} | null): AuthSession | null {
  if (!session?.user?.email) return null;
  return {
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    user: { id: session.user.id, email: session.user.email },
  };
}

/** Supabase implementation of AuthService (Single Responsibility: auth only). */
export class SupabaseAuthService implements AuthService {
  private readonly client: SupabaseClient;

  constructor(config: LibreRingConfig) {
    this.client = createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: { persistSession: true, autoRefreshToken: true },
    });
  }

  get supabase(): SupabaseClient {
    return this.client;
  }

  async signUp(email: string, password: string) {
    const { error } = await this.client.auth.signUp({ email, password });
    return error ? { ok: false, error: error.message } : { ok: true };
  }

  async signIn(email: string, password: string) {
    const { error } = await this.client.auth.signInWithPassword({ email, password });
    return error ? { ok: false, error: error.message } : { ok: true };
  }

  async signOut() {
    await this.client.auth.signOut();
  }

  async getSession(): Promise<AuthSession | null> {
    const { data } = await this.client.auth.getSession();
    return mapSession(data.session);
  }

  async getUser(): Promise<AuthUser | null> {
    const session = await this.getSession();
    return session?.user ?? null;
  }

  onAuthStateChange(callback: (session: AuthSession | null) => void) {
    const { data } = this.client.auth.onAuthStateChange((_event, session) => {
      callback(mapSession(session));
    });
    return () => data.subscription.unsubscribe();
  }
}

export function createAuthService(config: LibreRingConfig): SupabaseAuthService {
  return new SupabaseAuthService(config);
}
