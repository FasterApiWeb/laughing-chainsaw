import Foundation

struct ReadinessResult {
    let total: Int // 0-100
    let hrvScore: Int
    let restingHRScore: Int
    let temperatureScore: Int
    let sleepScore: Int
    let recoveryScore: Int

    var label: String {
        switch total {
        case 85...100: "Optimal"
        case 70..<85: "Good"
        case 50..<70: "Fair"
        default: "Pay attention"
        }
    }
}

enum ReadinessScoring {
    static func score(
        currentHRV: Double,
        baselineHRV: Double,
        currentRestingHR: Double,
        baselineRestingHR: Double,
        tempDeviation: Double,
        sleepScore: Int,
        recoveryIndex: Double // 0-1, based on activity vs rest balance
    ) -> ReadinessResult {
        // HRV: higher than baseline = good (35% weight)
        let hrvRatio = baselineHRV > 0 ? currentHRV / baselineHRV : 1.0
        let hrvScore = min(100, max(0, Int(hrvRatio * 80)))

        // Resting HR: lower than baseline = good (20% weight)
        let hrDiff = currentRestingHR - baselineRestingHR
        let restingHRScore = min(100, max(0, 80 - Int(hrDiff * 5)))

        // Temperature: close to baseline = good (15% weight)
        let tempScore = min(100, max(0, 100 - Int(abs(tempDeviation) * 50)))

        // Sleep: direct pass-through (20% weight)
        let sleepComp = min(100, max(0, sleepScore))

        // Recovery: based on training load vs rest (10% weight)
        let recoveryScore = min(100, max(0, Int(recoveryIndex * 100)))

        let total = Int(
            Double(hrvScore) * 0.35 +
            Double(restingHRScore) * 0.20 +
            Double(tempScore) * 0.15 +
            Double(sleepComp) * 0.20 +
            Double(recoveryScore) * 0.10
        )

        return ReadinessResult(
            total: min(100, max(0, total)),
            hrvScore: hrvScore,
            restingHRScore: restingHRScore,
            temperatureScore: tempScore,
            sleepScore: sleepComp,
            recoveryScore: recoveryScore
        )
    }
}
