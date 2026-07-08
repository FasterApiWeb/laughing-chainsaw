import Foundation
import HealthKit
import os

private let log = Logger(subsystem: "com.librering.app", category: "HealthKit")

@MainActor
final class HealthKitManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var lastWriteDate: Date?
    @Published var sampleCounts: [String: Int] = [:]

    private let store = HKHealthStore()
    private let source = "LibreRing"

    private var writeTypes: Set<HKSampleType> {
        Set([
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.bodyTemperature),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.respiratoryRate),
            HKCategoryType(.sleepAnalysis),
        ])
    }

    private var readTypes: Set<HKObjectType> {
        Set(writeTypes.map { $0 as HKObjectType })
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            log.info("HealthKit authorization granted")
        } catch {
            log.error("HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Write heart rate

    func writeHeartRate(_ readings: [IBIReading]) async {
        guard isAuthorized, !readings.isEmpty else { return }

        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let samples = readings.compactMap { reading -> HKQuantitySample? in
            guard reading.bpm > 30 && reading.bpm < 250 else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: reading.bpm),
                start: reading.timestamp,
                end: reading.timestamp,
                device: ouraDevice(),
                metadata: [HKMetadataKeyWasUserEntered: false]
            )
        }

        await saveSamples(samples, label: "heartRate")
    }

    // MARK: - Write HRV

    func writeHRV(_ rmssdValues: [(date: Date, rmssd: Double)]) async {
        guard isAuthorized, !rmssdValues.isEmpty else { return }

        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let unit = HKUnit.secondUnit(with: .milli)

        let samples = rmssdValues.map { val in
            HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: val.rmssd),
                start: val.date,
                end: val.date,
                device: ouraDevice(),
                metadata: nil
            )
        }

        await saveSamples(samples, label: "hrv")
    }

    // MARK: - Write SpO2

    func writeSpO2(_ readings: [SpO2Reading]) async {
        guard isAuthorized, !readings.isEmpty else { return }

        let type = HKQuantityType(.oxygenSaturation)
        let unit = HKUnit.percent()

        let samples = readings.compactMap { reading -> HKQuantitySample? in
            guard reading.percent >= 70 && reading.percent <= 100 else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: Double(reading.percent) / 100.0),
                start: reading.timestamp,
                end: reading.timestamp,
                device: ouraDevice(),
                metadata: nil
            )
        }

        await saveSamples(samples, label: "spo2")
    }

    // MARK: - Write temperature

    func writeTemperature(_ readings: [TemperatureReading]) async {
        guard isAuthorized, !readings.isEmpty else { return }

        let type = HKQuantityType(.bodyTemperature)
        let unit = HKUnit.degreeCelsius()

        let samples = readings.compactMap { reading -> HKQuantitySample? in
            guard reading.celsius > 30 && reading.celsius < 45 else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: reading.celsius),
                start: reading.timestamp,
                end: reading.timestamp,
                device: ouraDevice(),
                metadata: nil
            )
        }

        await saveSamples(samples, label: "temperature")
    }

    // MARK: - Write steps

    func writeSteps(_ readings: [StepReading]) async {
        guard isAuthorized, !readings.isEmpty else { return }

        let type = HKQuantityType(.stepCount)
        let unit = HKUnit.count()

        let samples = readings.map { reading in
            HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: Double(reading.count)),
                start: reading.timestamp,
                end: reading.timestamp.addingTimeInterval(60),
                device: ouraDevice(),
                metadata: nil
            )
        }

        await saveSamples(samples, label: "steps")
    }

    // MARK: - Write sleep

    func writeSleep(_ phases: [SleepPhaseReading]) async {
        guard isAuthorized, phases.count >= 2 else { return }

        let type = HKCategoryType(.sleepAnalysis)
        let sorted = phases.sorted { $0.timestamp < $1.timestamp }

        var samples: [HKCategorySample] = []
        for i in 0..<sorted.count - 1 {
            let start = sorted[i].timestamp
            let end = sorted[i + 1].timestamp
            guard end.timeIntervalSince(start) > 0 && end.timeIntervalSince(start) < 3600 * 4 else { continue }

            let value: HKCategoryValueSleepAnalysis = switch sorted[i].phase {
            case .awake: .awake
            case .light: .asleepCore
            case .deep: .asleepDeep
            case .rem: .asleepREM
            }

            samples.append(HKCategorySample(
                type: type,
                value: value.rawValue,
                start: start,
                end: end,
                device: ouraDevice(),
                metadata: nil
            ))
        }

        await saveSamples(samples, label: "sleep")
    }

    // MARK: - Write breathing rate

    func writeBreathingRate(_ rate: Double, at date: Date) async {
        guard isAuthorized, rate >= 8 && rate <= 30 else { return }

        let type = HKQuantityType(.respiratoryRate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: rate),
            start: date,
            end: date,
            device: ouraDevice(),
            metadata: nil
        )

        await saveSamples([sample], label: "breathingRate")
    }

    // MARK: - Write all from BLEManager

    func writeAll(from ble: BLEManager) async {
        await writeHeartRate(ble.ibiReadings)
        await writeSpO2(ble.spo2Readings)
        await writeTemperature(ble.temperatureReadings)
        await writeSteps(ble.stepReadings)
        await writeSleep(ble.sleepPhases)

        if !ble.ibiReadings.isEmpty {
            let intervals = ble.ibiReadings.map { Double($0.intervalMs) }
            let rmssd = HRVAnalysis.rmssd(from: intervals)
            let date = ble.ibiReadings.last?.timestamp ?? Date()
            await writeHRV([(date: date, rmssd: rmssd)])

            if let br = BreathingRate.estimate(from: intervals) {
                await writeBreathingRate(br, at: date)
            }
        }

        lastWriteDate = Date()
        log.info("Wrote all health data to HealthKit")
    }

    // MARK: - Private

    private func saveSamples(_ samples: [HKSample], label: String) async {
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            sampleCounts[label, default: 0] += samples.count
            log.info("Saved \(samples.count) \(label) samples to HealthKit")
        } catch {
            log.error("Failed to save \(label): \(error.localizedDescription)")
        }
    }

    private func ouraDevice() -> HKDevice {
        HKDevice(
            name: "Oura Ring",
            manufacturer: "Oura Health Oy",
            model: "Ring 4",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }
}
