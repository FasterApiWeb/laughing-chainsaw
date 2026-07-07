"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "./AuthProvider";

export function AuthGuard({ children }: { children: React.ReactNode }) {
  const { authed, accountExists } = useAuth();
  const router = useRouter();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (mounted && !authed) {
      router.replace(accountExists ? "/login" : "/signup");
    }
  }, [mounted, authed, accountExists, router]);

  if (!mounted || !authed) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-pulse text-foreground/50">Loading...</div>
      </div>
    );
  }

  return <>{children}</>;
}
