"use client";

import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip, CartesianGrid } from "recharts";

interface TrendChartProps {
  data: Array<{ date: string; value: number }>;
  label: string;
  color?: string;
  unit?: string;
}

export default function TrendChart({ data, label, color = "#3b82f6", unit = "" }: TrendChartProps) {
  if (data.length === 0) {
    return (
      <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
        <h3 className="text-sm font-medium mb-3">{label}</h3>
        <div className="h-40 flex items-center justify-center text-foreground/30 text-sm">No data yet</div>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
      <h3 className="text-sm font-medium mb-3">{label}</h3>
      <ResponsiveContainer width="100%" height={180}>
        <AreaChart data={data} margin={{ top: 5, right: 5, bottom: 5, left: 0 }}>
          <defs>
            <linearGradient id={`grad-${label}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.3} />
              <stop offset="100%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--color-foreground)" strokeOpacity={0.06} />
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
          />
          <Tooltip
            contentStyle={{
              backgroundColor: "var(--color-background)",
              border: "1px solid var(--color-foreground)",
              borderRadius: 8,
              fontSize: 12,
              opacity: 0.9,
            }}
            formatter={(value) => [`${value}${unit}`, label]}
          />
          <Area
            type="monotone"
            dataKey="value"
            stroke={color}
            strokeWidth={2}
            fill={`url(#grad-${label})`}
            dot={{ r: 3, fill: color }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
