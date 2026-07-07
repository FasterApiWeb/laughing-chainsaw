"use client";

import { useEffect, useState } from "react";
import { AuthProvider } from "@/components/AuthProvider";
import { AuthGuard } from "@/components/AuthGuard";
import NavSidebar from "@/components/NavSidebar";
import TrendChart from "@/components/TrendChart";
import DateRangePicker from "@/components/DateRangePicker";
import { getSummariesInRange } from "@/lib/queries";
import type { DailySummaryRecord } from "@/lib/db";
import { ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid, Legend } from "recharts";

function TrendsContent() {
  const [days, setDays] = useState(14);
  const [data, setData] = useState<DailySummaryRecord[]>([]);

  useEffect(() => {
    getSummariesInRange(days).then(setData);
  }, [days]);

  const hrData = data.filter((d) => d.avgHr > 0).map((d) => ({ date: d.date, value: Math.round(d.avgHr) }));
  const hrvData = data.filter((d) => d.avgHrv > 0).map((d) => ({ date: d.date, value: Math.round(d.avgHrv) }));
  const spo2Data = data.filter((d) => d.avgSpo2 > 0).map((d) => ({ date: d.date, value: Math.round(d.avgSpo2) }));
  const stepsData = data.filter((d) => d.totalSteps > 0).map((d) => ({ date: d.date, value: d.totalSteps }));
  const scoreData = data.filter((d) => d.sleepScore > 0 || d.readinessScore > 0 || d.activityScore > 0).map((d) => ({
    date: d.date,
    sleep: d.sleepScore,
    readiness: d.readinessScore,
    activity: d.activityScore,
  }));

  return (
    <div className="flex min-h-screen">
      <NavSidebar />
      <main className="flex-1 p-8 overflow-auto">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-semibold">Trends</h2>
          <DateRangePicker value={days} onChange={setDays} />
        </div>

        <div className="space-y-6">
          <TrendChart data={hrData} label="Heart Rate" unit=" bpm" color="#ef4444" />
          <TrendChart data={hrvData} label="HRV (RMSSD)" unit=" ms" color="#8b5cf6" />
          <TrendChart data={spo2Data} label="SpO2" unit="%" color="#3b82f6" />
          <TrendChart data={stepsData} label="Steps" color="#22c55e" />

          {scoreData.length > 0 && (
            <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
              <h3 className="text-sm font-medium mb-3">Scores</h3>
              <ResponsiveContainer width="100%" height={200}>
                <LineChart data={scoreData} margin={{ top: 5, right: 5, bottom: 5, left: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="var(--color-foreground)" strokeOpacity={0.06} />
                  <XAxis
                    dataKey="date"
                    tick={{ fontSize: 11, fill: "var(--color-foreground)", fillOpacity: 0.4 }}
                    tickFormatter={(v: string) => v.slice(5)}
                    axisLine={false}
                    tickLine={false}
                  />
                  <YAxis domain={[0, 100]} tick={{ fontSize: 11, fill: "var(--color-foreground)", fillOpacity: 0.4 }} axisLine={false} tickLine={false} width={30} />
                  <Tooltip
                    contentStyle={{ backgroundColor: "var(--color-background)", border: "1px solid var(--color-foreground)", borderRadius: 8, fontSize: 12, opacity: 0.9 }}
                  />
                  <Legend wrapperStyle={{ fontSize: 12 }} />
                  <Line type="monotone" dataKey="sleep" stroke="#6366f1" strokeWidth={2} dot={{ r: 3 }} name="Sleep" />
                  <Line type="monotone" dataKey="readiness" stroke="#10b981" strokeWidth={2} dot={{ r: 3 }} name="Readiness" />
                  <Line type="monotone" dataKey="activity" stroke="#f59e0b" strokeWidth={2} dot={{ r: 3 }} name="Activity" />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

export default function TrendsPage() {
  return (
    <AuthProvider>
      <AuthGuard>
        <TrendsContent />
      </AuthGuard>
    </AuthProvider>
  );
}
