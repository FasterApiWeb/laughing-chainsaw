"use client";

import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from "react";
import { isAuthenticated, logout as doLogout, getUser, hasAccount } from "@/lib/auth";

interface AuthContextValue {
  authed: boolean;
  accountExists: boolean;
  email: string | null;
  refresh: () => void;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue>({
  authed: false,
  accountExists: false,
  email: null,
  refresh: () => {},
  logout: () => {},
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [authed, setAuthed] = useState(() => isAuthenticated());
  const [accountExists, setAccountExists] = useState(() => hasAccount());
  const [email, setEmail] = useState<string | null>(() => getUser()?.email ?? null);

  const refresh = useCallback(() => {
    setAuthed(isAuthenticated());
    setAccountExists(hasAccount());
    setEmail(getUser()?.email ?? null);
  }, []);

  const logout = useCallback(() => {
    doLogout();
    refresh();
  }, [refresh]);

  return (
    <AuthContext.Provider value={{ authed, accountExists, email, refresh, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
