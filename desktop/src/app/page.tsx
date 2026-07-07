"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { isAuthenticated, hasAccount } from "@/lib/auth";

export default function Home() {
  const router = useRouter();

  useEffect(() => {
    if (isAuthenticated()) {
      router.replace("/dashboard");
    } else if (hasAccount()) {
      router.replace("/login");
    } else {
      router.replace("/signup");
    }
  }, [router]);

  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="animate-pulse text-foreground/50">Loading...</div>
    </div>
  );
}
