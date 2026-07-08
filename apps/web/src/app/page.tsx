"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { isAuthenticated, hasAccount } from "@/lib/auth";

export default function Home() {
  const router = useRouter();

  useEffect(() => {
    void (async () => {
      const authed = await isAuthenticated();
      if (authed) {
        router.replace("/dashboard");
        return;
      }
      const exists = await hasAccount();
      router.replace(exists ? "/login" : "/signup");
    })();
  }, [router]);

  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="animate-pulse text-foreground/50">Loading...</div>
    </div>
  );
}
