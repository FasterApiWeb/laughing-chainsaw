"use client";

import { useEffect, useState } from "react";
import { AuthProvider } from "@/components/AuthProvider";
import { AuthGuard } from "@/components/AuthGuard";
import NavSidebar from "@/components/NavSidebar";
import MetricCard from "@/components/MetricCard";
import ScoreRing from "@/components/ScoreRing";
import { getLatestMetrics, getLatestSummary } from "@/lib/queries";
import type { DailySummaryRecord, HeartRateRecord, SpO2Record, TemperatureRecord, StepRecord } from "@/lib/db";

function DashboardContent() {
  const [summary, setSummary] = useState<DailySummaryRecord | null>(null);
  const [metrics, setMetrics] = useState<{
    hr?: HeartRateRecord;
    spo2?: SpO2Record;
    temp?: TemperatureRecord;
    steps?: StepRecord;
  }>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const [s, m] = await Promise.all([getLatestSummary(), getLatestMetrics()]);
      setSummary(s ?? null);
      setMetrics(m);
      setLoading(false);
    })();
  }, []);

  const sleepScore = summary?.sleepScore ?? 0;
  const readinessScore = summary?.readinessScore ?? 0;
  const activityScore = summary?.activityScore ?? 0;
  const hasData = summary || metrics.hr || metrics.spo2;

  return (
    <div className="flex min-h-screen">
      <NavSidebar />
      <main className="flex-1 p-8 overflow-auto">
        <h2 className="text-xl font-semibold mb-6">Dashboard</h2>

        {loading ? (
          <div className="text-foreground/40">Loading...</div>
        ) : !hasData ? (
          <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-12 text-center">
            <p className="text-foreground/50 mb-2">No health data yet</p>
            <p className="text-sm text-foreground/30">
              Go to <a href="/upload" className="text-blue-500 hover:underline">Upload</a> to import your LibreRing or Oura export.
            </p>
          </div>
        ) : (
          <>
            <div className="flex gap-8 justify-center mb-8">
              <ScoreRing label="Sleep" score={sleepScore} sublabel={scoreLabel(sleepScore)} color="#6366f1" />
              <ScoreRing label="Readiness" score={readinessScore} sublabel={readinessLabel(readinessScore)} color="#10b981" />
              <ScoreRing label="Activity" score={activityScore} sublabel={activityLabel(activityScore)} color="#f59e0b" />
            </div>

            <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
              <MetricCard
                label="Heart Rate"
                value={metrics.hr ? Math.round(metrics.hr.bpm).toString() : summary?.avgHr ? Math.round(summary.avgHr).toString() : "--"}
                unit="bpm"
                icon="❤️"
                color="text-red-500"
              />
              <MetricCard
                label="HRV"
                value={summary?.avgHrv ? Math.round(summary.avgHrv).toString() : "--"}
                unit="ms"
                icon="📈"
                color="text-purple-500"
              />
              <MetricCard
                label="SpO2"
                value={metrics.spo2 ? metrics.spo2.percent.toString() : summary?.avgSpo2 ? Math.round(summary.avgSpo2).toString() : "--"}
                unit="%"
                icon="🩸"
                color="text-blue-500"
              />
              <MetricCard
                label="Temperature"
                value={metrics.temp ? metrics.temp.celsius.toFixed(1) : summary?.avgTemp ? summary.avgTemp.toFixed(1) : "--"}
                unit="°C"
                icon="🌡️"
                color="text-orange-500"
              />
              <MetricCard
                label="Steps"
                value={summary?.totalSteps ? summary.totalSteps.toLocaleString() : metrics.steps ? metrics.steps.count.toLocaleString() : "--"}
                icon="🚶"
                color="text-green-500"
              />
              <MetricCard
                label="Min HR"
                value={summary?.minHr ? Math.round(summary.minHr).toString() : "--"}
                unit="bpm"
                icon="💓"
                color="text-pink-500"
              />
            </div>

            {summary && (
              <p className="text-xs text-foreground/30 mt-6 text-center">
                Latest summary: {summary.date}
              </p>
            )}
          </>
        )}
      </main>
    </div>
  );
}

function scoreLabel(s: number) { return s >= 85 ? "Optimal" : s >= 70 ? "Good" : s >= 50 ? "Fair" : "Poor"; }
function readinessLabel(s: number) { return s >= 85 ? "Optimal" : s >= 70 ? "Good" : s >= 50 ? "Fair" : "Pay attention"; }
function activityLabel(s: number) { return s >= 85 ? "Optimal" : s >= 70 ? "Good" : s >= 50 ? "Fair" : "Low"; }

export default function DashboardPage() {
  return (
    <AuthProvider>
      <AuthGuard>
        <DashboardContent />
      </AuthGuard>
    </AuthProvider>
  );
}
