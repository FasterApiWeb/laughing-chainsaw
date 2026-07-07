import Foundation

struct ActivityResult {
    let total: Int
    let stepsScore: Int
    let activeCaloriesScore: Int
    let moveScore: Int
    let label: String

    init(total: Int, stepsScore: Int, activeCaloriesScore: Int, moveScore: Int) {
        self.total = min(100, max(0, total))
        self.stepsScore = stepsScore
        self.activeCaloriesScore = activeCaloriesScore
        self.moveScore = moveScore
        self.label = switch self.total {
        case 85...100: "Optimal"
        case 70..<85: "Good"
        case 50..<70: "Fair"
        default: "Low"
        }
    }
}

enum ActivityScoring {
    private static let defaultStepGoal: UInt32 = 10000
    private static let defaultCalGoal: Double = 350

    static func score(
        totalSteps: UInt32,
        stepGoal: UInt32 = defaultStepGoal,
        activeCalories: Double = 0,
        calorieGoal: Double = defaultCalGoal,
        inactiveMinutes: Double = 0
    ) -> ActivityResult {
        let stepsScore = piecewise(
            ratio: Double(totalSteps) / Double(max(1, stepGoal)),
            points: [(0, 0), (0.5, 25), (1.0, 85), (1.5, 100)]
        )

        let calScore = piecewise(
            ratio: activeCalories / max(1, calorieGoal),
            points: [(0, 0), (0.5, 25), (1.0, 85), (1.5, 100)]
        )

        // Penalize long inactivity stretches (>8 hours sedentary in 16 waking hours)
        let moveRatio = max(0, 1.0 - (inactiveMinutes / 480.0))
        let moveScore = piecewise(
            ratio: moveRatio,
            points: [(0, 0), (0.3, 40), (0.7, 80), (1.0, 100)]
        )

        let total = Int(
            Double(stepsScore) * 0.40 +
            Double(calScore) * 0.35 +
            Double(moveScore) * 0.25
        )

        return ActivityResult(total: total, stepsScore: stepsScore, activeCaloriesScore: calScore, moveScore: moveScore)
    }

    static func estimateCalories(steps: UInt32, weightKg: Double = 70) -> Double {
        Double(steps) * 0.04 * weightKg / 70.0
    }

    private static func piecewise(ratio: Double, points: [(x: Double, y: Double)]) -> Int {
        let r = max(0, ratio)
        for i in 1..<points.count {
            if r <= points[i].x {
                let x0 = points[i - 1].x
                let y0 = points[i - 1].y
                let x1 = points[i].x
                let y1 = points[i].y
                let t = (r - x0) / (x1 - x0)
                return Int(y0 + t * (y1 - y0))
            }
        }
        return Int(points.last?.y ?? 100)
    }
}
