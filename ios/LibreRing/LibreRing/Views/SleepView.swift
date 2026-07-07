import SwiftUI
import Charts

struct SleepView: View {
    @EnvironmentObject var ble: BLEManager

    private var sleepScore: SleepScore? {
        SleepScoring.analyze(phases: ble.sleepPhases)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if ble.sleepPhases.isEmpty {
                    ContentUnavailableView(
                        "No Sleep Data",
                        systemImage: "bed.double",
                        description: Text("Wear your ring tonight. Sleep data will appear here after your next sync.")
                    )
                } else {
                    VStack(spacing: 16) {
                        if let score = sleepScore {
                            ScoreCard(title: "Sleep Score", score: score.total, label: score.label, color: .indigo)

                            HStack(spacing: 12) {
                                MiniScore(title: "Duration", score: score.durationScore, color: .blue)
                                MiniScore(title: "Efficiency", score: score.efficiencyScore, color: .green)
                                MiniScore(title: "Deep", score: score.deepScore, color: .purple)
                                MiniScore(title: "REM", score: score.remScore, color: .pink)
                            }
                        }

                        SleepStagesChart(phases: ble.sleepPhases)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Sleep")
        }
    }
}

struct MiniScore: View {
    let title: String
    let score: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SleepStagesChart: View {
    let phases: [SleepPhaseReading]

    private var sortedPhases: [SleepPhaseReading] {
        phases.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Sleep Stages")
                .font(.headline)

            if #available(iOS 17.0, *) {
                Chart {
                    ForEach(Array(sortedPhases.enumerated()), id: \.offset) { _, phase in
                        BarMark(
                            x: .value("Time", phase.timestamp),
                            y: .value("Stage", phaseLabel(phase.phase))
                        )
                        .foregroundStyle(phaseColor(phase.phase))
                    }
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
            }

            HStack(spacing: 16) {
                LegendDot(color: .red.opacity(0.6), label: "Awake")
                LegendDot(color: .blue.opacity(0.6), label: "Light")
                LegendDot(color: .purple, label: "Deep")
                LegendDot(color: .pink, label: "REM")
            }
            .font(.caption)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func phaseLabel(_ phase: SleepPhase) -> String {
        switch phase {
        case .awake: "Awake"
        case .light: "Light"
        case .deep: "Deep"
        case .rem: "REM"
        }
    }

    private func phaseColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .awake: .red.opacity(0.6)
        case .light: .blue.opacity(0.6)
        case .deep: .purple
        case .rem: .pink
        }
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
