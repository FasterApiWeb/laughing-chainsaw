import SwiftUI
import Charts

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: String
    let value: Double
}

struct TrendsView: View {
    @State private var summaries: [(date: String, steps: Int, avgHR: Double, avgHRV: Double, avgSpO2: Double, sleepScore: Int, readinessScore: Int, activityScore: Int)] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                if summaries.isEmpty {
                    ContentUnavailableView(
                        "No Trend Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Sync your ring daily to build up trends. Data appears after your first full day.")
                    )
                } else {
                    VStack(spacing: 20) {
                        TrendChart(
                            title: "Heart Rate",
                            unit: "BPM",
                            color: .red,
                            data: summaries.compactMap { s in
                                s.avgHR > 0 ? TrendPoint(date: s.date, value: s.avgHR) : nil
                            }
                        )

                        TrendChart(
                            title: "HRV (RMSSD)",
                            unit: "ms",
                            color: .blue,
                            data: summaries.compactMap { s in
                                s.avgHRV > 0 ? TrendPoint(date: s.date, value: s.avgHRV) : nil
                            }
                        )

                        TrendChart(
                            title: "SpO2",
                            unit: "%",
                            color: .cyan,
                            data: summaries.compactMap { s in
                                s.avgSpO2 > 0 ? TrendPoint(date: s.date, value: s.avgSpO2) : nil
                            }
                        )

                        TrendChart(
                            title: "Steps",
                            unit: "steps",
                            color: .green,
                            data: summaries.compactMap { s in
                                s.steps > 0 ? TrendPoint(date: s.date, value: Double(s.steps)) : nil
                            }
                        )

                        ScoreTrendChart(
                            title: "Scores",
                            data: summaries.compactMap { s in
                                guard s.sleepScore > 0 || s.readinessScore > 0 else { return nil }
                                return (date: s.date, sleep: s.sleepScore, readiness: s.readinessScore, activity: s.activityScore)
                            }
                        )
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Trends")
            .onAppear { loadData() }
        }
    }

    private func loadData() {
        summaries = LocalStore.shared.loadDailySummaries(days: 14)
    }
}

struct TrendChart: View {
    let title: String
    let unit: String
    let color: Color
    let data: [TrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let latest = data.last {
                    Text("\(Int(latest.value)) \(unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if data.count >= 2 {
                Chart(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(color.opacity(0.1))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(color)
                    .symbolSize(20)
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
            } else {
                Text("Need at least 2 days of data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ScoreTrendChart: View {
    let title: String
    let data: [(date: String, sleep: Int, readiness: Int, activity: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if data.count >= 2 {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Score", entry.sleep),
                            series: .value("Type", "Sleep")
                        )
                        .foregroundStyle(.indigo)

                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Score", entry.readiness),
                            series: .value("Type", "Readiness")
                        )
                        .foregroundStyle(.orange)

                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Score", entry.activity),
                            series: .value("Type", "Activity")
                        )
                        .foregroundStyle(.green)
                    }
                }
                .frame(height: 160)
                .chartForegroundStyleScale([
                    "Sleep": Color.indigo,
                    "Readiness": Color.orange,
                    "Activity": Color.green,
                ])

                HStack(spacing: 16) {
                    LegendDot(color: .indigo, label: "Sleep")
                    LegendDot(color: .orange, label: "Readiness")
                    LegendDot(color: .green, label: "Activity")
                }
                .font(.caption)
            } else {
                Text("Need at least 2 days of data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
