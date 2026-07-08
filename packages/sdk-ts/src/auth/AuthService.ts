import type { AuthSession, AuthUser, LibreRingConfig } from "../types.js";

/** Auth port — Dependency Inversion: clients depend on this, not Supabase directly. */
export interface AuthService {
  signUp(email: string, password: string): Promise<{ ok: boolean; error?: string }>;
  signIn(email: string, password: string): Promise<{ ok: boolean; error?: string }>;
  signOut(): Promise<void>;
  getSession(): Promise<AuthSession | null>;
  getUser(): Promise<AuthUser | null>;
  onAuthStateChange(callback: (session: AuthSession | null) => void): () => void;
}

export type AuthServiceFactory = (config: LibreRingConfig) => AuthService;
