"use client";

import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from "react";
import {
  isAuthenticated,
  logout as doLogout,
  getUser,
  hasAccount,
  onAuthStateChange,
} from "@/lib/auth";
import { isCloudEnabled } from "@/lib/config";

interface AuthContextValue {
  authed: boolean;
  accountExists: boolean;
  email: string | null;
  cloudEnabled: boolean;
  loading: boolean;
  refresh: () => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue>({
  authed: false,
  accountExists: false,
  email: null,
  cloudEnabled: false,
  loading: true,
  refresh: async () => {},
  logout: async () => {},
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const cloudEnabled = isCloudEnabled();
  const [authed, setAuthed] = useState(false);
  const [accountExists, setAccountExists] = useState(false);
  const [email, setEmail] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    const [a, h, u] = await Promise.all([isAuthenticated(), hasAccount(), getUser()]);
    setAuthed(a);
    setAccountExists(h);
    setEmail(u?.email ?? null);
    setLoading(false);
  }, []);

  useEffect(() => {
    const unsub = onAuthStateChange(() => {
      void refresh();
    });
    // Hydrate session on mount (Supabase restore + local fallback)
    // eslint-disable-next-line react-hooks/set-state-in-effect -- auth hydration on mount
    void refresh();
    return unsub;
  }, [refresh]);

  const logout = useCallback(async () => {
    await doLogout();
    await refresh();
  }, [refresh]);

  return (
    <AuthContext.Provider
      value={{ authed, accountExists, email, cloudEnabled, loading, refresh, logout }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
