"use client";

import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, Legend } from "recharts";

interface SleepDay {
  date: string;
  awake: number;
  light: number;
  deep: number;
  rem: number;
}

interface SleepStagesChartProps {
  data: SleepDay[];
}

export default function SleepStagesChart({ data }: SleepStagesChartProps) {
  if (data.length === 0) {
    return (
      <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
        <h3 className="text-sm font-medium mb-3">Sleep Stages</h3>
        <div className="h-48 flex items-center justify-center text-foreground/30 text-sm">No data yet</div>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
      <h3 className="text-sm font-medium mb-3">Sleep Stages</h3>
      <ResponsiveContainer width="100%" height={220}>
        <BarChart data={data} margin={{ top: 5, right: 5, bottom: 5, left: 0 }}>
          <XAxis
            dataKey="date"
            tick={{ fontSize: 11, fill: "var(--color-foreground)", fillOpacity: 0.4 }}
            tickFormatter={(v: string) => v.slice(5)}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={{ fontSize: 11, fill: "var(--color-foreground)", fillOpacity: 0.4 }}
            axisLine={false}
            tickLine={false}
            width={40}
            label={{ value: "min", position: "insideTopLeft", fontSize: 10, fill: "var(--color-foreground)", fillOpacity: 0.3 }}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: "var(--color-background)",
              border: "1px solid var(--color-foreground)",
              borderRadius: 8,
              fontSize: 12,
              opacity: 0.9,
            }}
            formatter={(value, name) => [`${value} min`, `${name}`]}
          />
          <Legend wrapperStyle={{ fontSize: 12 }} />
          <Bar dataKey="deep" stackId="sleep" fill="#6366f1" name="Deep" radius={[0, 0, 0, 0]} />
          <Bar dataKey="rem" stackId="sleep" fill="#8b5cf6" name="REM" />
          <Bar dataKey="light" stackId="sleep" fill="#a78bfa" name="Light" />
          <Bar dataKey="awake" stackId="sleep" fill="#e5e7eb" name="Awake" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
