import Foundation

struct BaselineValue {
    let mean: Double
    let deviation: Double
    let sampleCount: Int
    let lastUpdated: Date
}

enum PersonalBaseline {
    // Asymmetric EMA: rises slowly, drops fast (matches Oura's approach)
    // Alpha-up = 0.05 (slow adaptation to improvements)
    // Alpha-down = 0.15 (fast adaptation to degradation)
    private static let alphaUp = 0.05
    private static let alphaDown = 0.15
    private static let minimumSamples = 3
    private static let windowDays = 14

    static func compute(
        currentValue: Double,
        previousBaseline: BaselineValue?
    ) -> BaselineValue {
        guard let prev = previousBaseline, prev.sampleCount >= minimumSamples else {
            let count = (previousBaseline?.sampleCount ?? 0) + 1
            let oldMean = previousBaseline?.mean ?? currentValue
            let newMean = oldMean + (currentValue - oldMean) / Double(count)
            let oldDev = previousBaseline?.deviation ?? 0
            let newDev = oldDev + (abs(currentValue - newMean) - oldDev) / Double(count)
            return BaselineValue(mean: newMean, deviation: max(newDev, 1.0), sampleCount: count, lastUpdated: Date())
        }

        let alpha = currentValue > prev.mean ? alphaUp : alphaDown
        let newMean = prev.mean + alpha * (currentValue - prev.mean)
        let newDev = prev.deviation + alpha * (abs(currentValue - newMean) - prev.deviation)

        return BaselineValue(
            mean: newMean,
            deviation: max(newDev, 1.0),
            sampleCount: prev.sampleCount + 1,
            lastUpdated: Date()
        )
    }

    static func deviationFromBaseline(value: Double, baseline: BaselineValue) -> Double {
        guard baseline.deviation > 0 else { return 0 }
        return (value - baseline.mean) / baseline.deviation
    }

    static func computeFromHistory(_ values: [Double]) -> BaselineValue? {
        guard !values.isEmpty else { return nil }
        let window = values.suffix(windowDays)
        let sorted = window.sorted()
        let median = sorted[sorted.count / 2]
        let mean = window.reduce(0, +) / Double(window.count)
        let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window.count)
        let dev = sqrt(variance)
        return BaselineValue(mean: median, deviation: max(dev, 1.0), sampleCount: window.count, lastUpdated: Date())
    }
}
