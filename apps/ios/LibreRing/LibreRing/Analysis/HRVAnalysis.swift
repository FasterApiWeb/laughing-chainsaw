import Foundation

enum HRVAnalysis {
    /// Root Mean Square of Successive Differences
    static func rmssd(from intervals: [Double]) -> Double {
        guard intervals.count >= 2 else { return 0 }
        var sumSquared = 0.0
        for i in 1..<intervals.count {
            let diff = intervals[i] - intervals[i - 1]
            sumSquared += diff * diff
        }
        return sqrt(sumSquared / Double(intervals.count - 1))
    }

    /// Standard Deviation of NN intervals
    static func sdnn(from intervals: [Double]) -> Double {
        guard intervals.count >= 2 else { return 0 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervals.count - 1)
        return sqrt(variance)
    }

    /// Percentage of successive differences > 50ms
    static func pnn50(from intervals: [Double]) -> Double {
        guard intervals.count >= 2 else { return 0 }
        var count = 0
        for i in 1..<intervals.count {
            if abs(intervals[i] - intervals[i - 1]) > 50 {
                count += 1
            }
        }
        return Double(count) / Double(intervals.count - 1) * 100.0
    }
}
