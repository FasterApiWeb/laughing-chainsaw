"use client";

import { useEffect, useState } from "react";
import { AuthProvider } from "@/components/AuthProvider";
import { AuthGuard } from "@/components/AuthGuard";
import NavSidebar from "@/components/NavSidebar";
import ScoreRing from "@/components/ScoreRing";
import SleepStagesChart from "@/components/SleepStagesChart";
import DateRangePicker from "@/components/DateRangePicker";
import { getSummariesInRange } from "@/lib/queries";
import { db } from "@/lib/db";

interface SleepDay {
  date: string;
  awake: number;
  light: number;
  deep: number;
  rem: number;
}

function SleepContent() {
  const [days, setDays] = useState(14);
  const [sleepScore, setSleepScore] = useState(0);
  const [stagesData, setStagesData] = useState<SleepDay[]>([]);

  useEffect(() => {
    (async () => {
      const summaries = await getSummariesInRange(days);
      if (summaries.length > 0) {
        setSleepScore(summaries[summaries.length - 1].sleepScore);
      }

      const cutoff = (Date.now() - days * 86400000) / 1000;
      const phases = await db.sleepPhase
        .where("timestamp")
        .aboveOrEqual(cutoff)
        .sortBy("timestamp");

      const byDate = new Map<string, { awake: number; light: number; deep: number; rem: number }>();
      for (let i = 0; i < phases.length - 1; i++) {
        const date = new Date(phases[i].timestamp * 1000).toISOString().slice(0, 10);
        const durationMin = (phases[i + 1].timestamp - phases[i].timestamp) / 60;
        if (!byDate.has(date)) byDate.set(date, { awake: 0, light: 0, deep: 0, rem: 0 });
        const entry = byDate.get(date)!;
        switch (phases[i].phase) {
          case 0: entry.awake += durationMin; break;
          case 1: entry.light += durationMin; break;
          case 2: entry.deep += durationMin; break;
          case 3: entry.rem += durationMin; break;
        }
      }

      setStagesData(
        Array.from(byDate.entries())
          .map(([date, d]) => ({
            date,
            awake: Math.round(d.awake),
            light: Math.round(d.light),
            deep: Math.round(d.deep),
            rem: Math.round(d.rem),
          }))
          .sort((a, b) => a.date.localeCompare(b.date))
      );
    })();
  }, [days]);

  const label = sleepScore >= 85 ? "Optimal" : sleepScore >= 70 ? "Good" : sleepScore >= 50 ? "Fair" : "Poor";

  return (
    <div className="flex min-h-screen">
      <NavSidebar />
      <main className="flex-1 p-8 overflow-auto">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-semibold">Sleep</h2>
          <DateRangePicker value={days} onChange={setDays} />
        </div>

        <div className="flex justify-center mb-8">
          <ScoreRing label="Sleep Score" score={sleepScore} sublabel={label} color="#6366f1" size={140} />
        </div>

        <SleepStagesChart data={stagesData} />

        {stagesData.length === 0 && (
          <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-8 text-center mt-6">
            <p className="text-foreground/50 text-sm">No sleep phase data available.</p>
            <p className="text-foreground/30 text-xs mt-1">Import data with sleep phases to see the breakdown.</p>
          </div>
        )}
      </main>
    </div>
  );
}

export default function SleepPage() {
  return (
    <AuthProvider>
      <AuthGuard>
        <SleepContent />
      </AuthGuard>
    </AuthProvider>
  );
}
