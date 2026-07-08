import Foundation

struct SleepScore {
    let total: Int // 0-100
    let durationScore: Int
    let efficiencyScore: Int
    let deepScore: Int
    let remScore: Int
    let latencyScore: Int

    var label: String {
        switch total {
        case 85...100: "Optimal"
        case 70..<85: "Good"
        case 50..<70: "Fair"
        default: "Poor"
        }
    }
}

enum SleepScoring {
    static func score(
        totalSleepMinutes: Double,
        timeInBedMinutes: Double,
        deepPercent: Double,
        remPercent: Double,
        latencyMinutes: Double
    ) -> SleepScore {
        // Duration: 7-9 hours optimal
        let durationScore = clampedScore(
            value: totalSleepMinutes,
            optimal: 480, // 8 hours
            min: 300,     // 5 hours
            max: 600      // 10 hours
        )

        // Efficiency: time asleep / time in bed
        let efficiency = timeInBedMinutes > 0 ? (totalSleepMinutes / timeInBedMinutes) * 100 : 0
        let efficiencyScore = min(100, max(0, Int(efficiency)))

        // Deep sleep: 15-25% optimal
        let deepScore = clampedScore(value: deepPercent, optimal: 20, min: 5, max: 35)

        // REM: 20-25% optimal
        let remScore = clampedScore(value: remPercent, optimal: 22, min: 10, max: 35)

        // Latency: <15 min optimal
        let latencyScore = max(0, min(100, 100 - Int(max(0, latencyMinutes - 5) * 3)))

        let total = Int(
            Double(durationScore) * 0.30 +
            Double(efficiencyScore) * 0.25 +
            Double(deepScore) * 0.20 +
            Double(remScore) * 0.15 +
            Double(latencyScore) * 0.10
        )

        return SleepScore(
            total: min(100, max(0, total)),
            durationScore: durationScore,
            efficiencyScore: efficiencyScore,
            deepScore: deepScore,
            remScore: remScore,
            latencyScore: latencyScore
        )
    }

    static func analyze(phases: [SleepPhaseReading]) -> SleepScore? {
        guard phases.count >= 2 else { return nil }
        let sorted = phases.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { return nil }

        let totalBedMinutes = last.timestamp.timeIntervalSince(first.timestamp) / 60
        guard totalBedMinutes > 0 else { return nil }

        var phaseDurations: [SleepPhase: Double] = [:]
        for i in 0..<sorted.count - 1 {
            let duration = sorted[i + 1].timestamp.timeIntervalSince(sorted[i].timestamp) / 60
            phaseDurations[sorted[i].phase, default: 0] += duration
        }

        let awakeMin = phaseDurations[.awake] ?? 0
        let sleepMin = totalBedMinutes - awakeMin
        let deepPercent = sleepMin > 0 ? ((phaseDurations[.deep] ?? 0) / sleepMin) * 100 : 0
        let remPercent = sleepMin > 0 ? ((phaseDurations[.rem] ?? 0) / sleepMin) * 100 : 0

        // Latency: time from first phase to first non-awake phase
        var latency = 0.0
        if sorted.first?.phase == .awake, let firstSleep = sorted.first(where: { $0.phase != .awake }) {
            latency = firstSleep.timestamp.timeIntervalSince(first.timestamp) / 60
        }

        return score(
            totalSleepMinutes: sleepMin,
            timeInBedMinutes: totalBedMinutes,
            deepPercent: deepPercent,
            remPercent: remPercent,
            latencyMinutes: latency
        )
    }

    private static func clampedScore(value: Double, optimal: Double, min: Double, max: Double) -> Int {
        if value >= optimal {
            let excess = value - optimal
            let range = max - optimal
            return range > 0 ? Swift.max(0, 100 - Int((excess / range) * 30)) : 100
        } else {
            let deficit = optimal - value
            let range = optimal - min
            return range > 0 ? Swift.max(0, 100 - Int((deficit / range) * 100)) : 0
        }
    }
}
