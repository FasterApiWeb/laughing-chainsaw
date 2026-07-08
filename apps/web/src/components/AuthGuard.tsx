"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "./AuthProvider";

export function AuthGuard({ children }: { children: React.ReactNode }) {
  const { authed, accountExists, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !authed) {
      router.replace(accountExists ? "/login" : "/signup");
    }
  }, [loading, authed, accountExists, router]);

  if (loading || !authed) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-pulse text-foreground/50">Loading...</div>
      </div>
    );
  }

  return <>{children}</>;
}
