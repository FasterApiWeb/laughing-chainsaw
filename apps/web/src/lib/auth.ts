import { getClient } from "./client";
import { isCloudEnabled } from "./config";

const LOCAL_STORAGE_KEY = "librering_user";
const LOCAL_SESSION_KEY = "librering_session";

interface StoredUser {
  email: string;
  passwordHash: string;
  createdAt: string;
}

async function deriveHash(password: string, salt: string): Promise<string> {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    enc.encode(password),
    "PBKDF2",
    false,
    ["deriveBits"]
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: enc.encode(salt), iterations: 100_000, hash: "SHA-256" },
    keyMaterial,
    256
  );
  return Array.from(new Uint8Array(bits))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Cloud auth via Supabase when env is configured; local-only fallback otherwise. */
export async function signup(
  email: string,
  password: string
): Promise<{ ok: boolean; error?: string }> {
  const cloud = getClient();
  if (cloud) return cloud.auth.signUp(email, password);
  return localSignup(email, password);
}

export async function login(
  email: string,
  password: string
): Promise<{ ok: boolean; error?: string }> {
  const cloud = getClient();
  if (cloud) return cloud.auth.signIn(email, password);
  return localLogin(email, password);
}

export async function logout(): Promise<void> {
  const cloud = getClient();
  if (cloud) {
    await cloud.auth.signOut();
    return;
  }
  if (typeof window !== "undefined") {
    sessionStorage.removeItem(LOCAL_SESSION_KEY);
  }
}

export async function isAuthenticated(): Promise<boolean> {
  const cloud = getClient();
  if (cloud) {
    const session = await cloud.auth.getSession();
    return session !== null;
  }
  if (typeof window === "undefined") return false;
  return sessionStorage.getItem(LOCAL_SESSION_KEY) === "active";
}

export async function getUser(): Promise<{ email: string; createdAt?: string } | null> {
  const cloud = getClient();
  if (cloud) {
    const user = await cloud.auth.getUser();
    return user ? { email: user.email } : null;
  }
  if (typeof window === "undefined") return null;
  const raw = localStorage.getItem(LOCAL_STORAGE_KEY);
  if (!raw) return null;
  const user: StoredUser = JSON.parse(raw);
  return { email: user.email, createdAt: user.createdAt };
}

export async function deleteAccount(): Promise<void> {
  await logout();
  if (!isCloudEnabled() && typeof window !== "undefined") {
    localStorage.removeItem(LOCAL_STORAGE_KEY);
    sessionStorage.removeItem(LOCAL_SESSION_KEY);
  }
  // Supabase user deletion requires service role — document in settings UI
}

export async function hasAccount(): Promise<boolean> {
  const cloud = getClient();
  if (cloud) {
    const session = await cloud.auth.getSession();
    return session !== null;
  }
  if (typeof window === "undefined") return false;
  return localStorage.getItem(LOCAL_STORAGE_KEY) !== null;
}

export function onAuthStateChange(callback: () => void): () => void {
  const cloud = getClient();
  if (cloud) {
    return cloud.auth.onAuthStateChange(() => callback());
  }
  return () => {};
}

async function localSignup(email: string, password: string) {
  if (typeof window === "undefined") return { ok: false, error: "Not in browser" };
  const existing = localStorage.getItem(LOCAL_STORAGE_KEY);
  if (existing) return { ok: false, error: "Account already exists. Sign in instead." };

  const hash = await deriveHash(password, email.toLowerCase());
  const user: StoredUser = {
    email: email.toLowerCase(),
    passwordHash: hash,
    createdAt: new Date().toISOString(),
  };
  localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(user));
  sessionStorage.setItem(LOCAL_SESSION_KEY, "active");
  return { ok: true };
}

async function localLogin(email: string, password: string) {
  if (typeof window === "undefined") return { ok: false, error: "Not in browser" };
  const raw = localStorage.getItem(LOCAL_STORAGE_KEY);
  if (!raw) return { ok: false, error: "No account found. Sign up first." };

  const user: StoredUser = JSON.parse(raw);
  if (user.email !== email.toLowerCase()) return { ok: false, error: "Email does not match." };

  const hash = await deriveHash(password, email.toLowerCase());
  if (hash !== user.passwordHash) return { ok: false, error: "Incorrect password." };

  sessionStorage.setItem(LOCAL_SESSION_KEY, "active");
  return { ok: true };
}
