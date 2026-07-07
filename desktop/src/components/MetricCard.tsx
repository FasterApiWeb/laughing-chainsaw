"use client";

interface MetricCardProps {
  label: string;
  value: string;
  unit?: string;
  icon: string;
  color?: string;
}

export default function MetricCard({ label, value, unit, icon, color = "text-blue-500" }: MetricCardProps) {
  return (
    <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
      <div className="flex items-center gap-2 mb-3">
        <span className={`text-lg ${color}`}>{icon}</span>
        <span className="text-sm text-foreground/50">{label}</span>
      </div>
      <div className="flex items-baseline gap-1">
        <span className="text-2xl font-semibold tabular-nums">{value}</span>
        {unit && <span className="text-sm text-foreground/40">{unit}</span>}
      </div>
    </div>
  );
}
