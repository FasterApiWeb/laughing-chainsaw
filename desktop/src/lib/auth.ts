const STORAGE_KEY = "librering_user";
const SESSION_KEY = "librering_session";

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
    { name: "PBKDF2", salt: enc.encode(salt), iterations: 100000, hash: "SHA-256" },
    keyMaterial,
    256
  );
  return Array.from(new Uint8Array(bits))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function signup(email: string, password: string): Promise<{ ok: boolean; error?: string }> {
  if (typeof window === "undefined") return { ok: false, error: "Not in browser" };
  const existing = localStorage.getItem(STORAGE_KEY);
  if (existing) return { ok: false, error: "Account already exists. Sign in instead." };

  const hash = await deriveHash(password, email.toLowerCase());
  const user: StoredUser = { email: email.toLowerCase(), passwordHash: hash, createdAt: new Date().toISOString() };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(user));
  sessionStorage.setItem(SESSION_KEY, "active");
  return { ok: true };
}

export async function login(email: string, password: string): Promise<{ ok: boolean; error?: string }> {
  if (typeof window === "undefined") return { ok: false, error: "Not in browser" };
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return { ok: false, error: "No account found. Sign up first." };

  const user: StoredUser = JSON.parse(raw);
  if (user.email !== email.toLowerCase()) return { ok: false, error: "Email does not match." };

  const hash = await deriveHash(password, email.toLowerCase());
  if (hash !== user.passwordHash) return { ok: false, error: "Incorrect password." };

  sessionStorage.setItem(SESSION_KEY, "active");
  return { ok: true };
}

export function logout(): void {
  sessionStorage.removeItem(SESSION_KEY);
}

export function isAuthenticated(): boolean {
  if (typeof window === "undefined") return false;
  return sessionStorage.getItem(SESSION_KEY) === "active";
}

export function getUser(): { email: string; createdAt: string } | null {
  if (typeof window === "undefined") return null;
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return null;
  const user: StoredUser = JSON.parse(raw);
  return { email: user.email, createdAt: user.createdAt };
}

export function deleteAccount(): void {
  localStorage.removeItem(STORAGE_KEY);
  sessionStorage.removeItem(SESSION_KEY);
}

export function hasAccount(): boolean {
  if (typeof window === "undefined") return false;
  return localStorage.getItem(STORAGE_KEY) !== null;
}
