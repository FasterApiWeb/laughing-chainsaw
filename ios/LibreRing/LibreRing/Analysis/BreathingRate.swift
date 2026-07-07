import Foundation

enum BreathingRate {
    static func estimate(from ibiIntervals: [Double]) -> Double? {
        guard ibiIntervals.count >= 30 else { return nil }

        let diffs = (1..<ibiIntervals.count).map { ibiIntervals[$0] - ibiIntervals[$0 - 1] }
        guard diffs.count >= 10 else { return nil }

        // Respiratory sinus arrhythmia: IBI oscillates with breathing
        // Count zero-crossings in the IBI difference signal to estimate breath cycles
        var crossings = 0
        for i in 1..<diffs.count {
            if (diffs[i - 1] > 0 && diffs[i] < 0) || (diffs[i - 1] < 0 && diffs[i] > 0) {
                crossings += 1
            }
        }

        let totalTimeSeconds = ibiIntervals.reduce(0, +) / 1000.0
        guard totalTimeSeconds > 0 else { return nil }

        // Each full breath cycle has 2 zero-crossings (up→down, down→up)
        let breathCycles = Double(crossings) / 2.0
        let breathsPerMinute = breathCycles / (totalTimeSeconds / 60.0)

        // Valid respiratory range: 8-30 breaths/min
        guard breathsPerMinute >= 8 && breathsPerMinute <= 30 else { return nil }
        return (breathsPerMinute * 10).rounded() / 10
    }
}
