import Foundation

// SpO2 calibration from R-ratio using quadratic fit
// Formula: SpO2(%) = a*r^2 + b*r + c, clamped to 85-100
// Coefficients from open_oura reverse engineering of Oura's libappecore.so
enum SpO2Calibration {
    struct Coefficients {
        let a: Double
        let b: Double
        let c: Double
    }

    static let gen4 = Coefficients(a: -13.4, b: -5.1, c: 105.2)
    static let ring5 = Coefficients(a: -12.1, b: -6.9, c: 106.3)

    static func calibrate(rRatio: Double, coefficients: Coefficients = gen4) -> UInt8 {
        let raw = coefficients.a * rRatio * rRatio + coefficients.b * rRatio + coefficients.c
        return UInt8(min(100, max(85, Int(raw.rounded()))))
    }

    static func nightlyAverage(readings: [SpO2Reading]) -> Double? {
        guard !readings.isEmpty else { return nil }
        let valid = readings.filter { $0.percent >= 85 && $0.percent <= 100 }
        guard !valid.isEmpty else { return nil }
        return Double(valid.reduce(0) { $0 + Int($1.percent) }) / Double(valid.count)
    }

    static func belowThresholdPercent(readings: [SpO2Reading], threshold: UInt8 = 90) -> Double {
        guard !readings.isEmpty else { return 0 }
        let below = readings.filter { $0.percent < threshold }.count
        return Double(below) / Double(readings.count) * 100.0
    }
}
