import Foundation
import CryptoKit

// MARK: - Auth states

enum AuthResult: UInt8 {
    case success = 0x00
    case authenticationError = 0x01
    case inFactoryReset = 0x02
    case notOriginalDevice = 0x03
}

// MARK: - Ring mode

enum RingMode: UInt8 {
    case normal = 0x00
    case fastHR = 0x01
    case deepSleep = 0x02
}

// MARK: - Feature IDs

enum FeatureID: UInt8 {
    case backgroundDFU = 0x00
    case researchData = 0x01
    case daytimeHR = 0x02
    case exerciseHR = 0x03
    case spo2 = 0x04
    case bundling = 0x05
    case encryptedAPI = 0x06
    case tapToTag = 0x07
    case restingHR = 0x08
    case appAuth = 0x09
    case bleMode = 0x0A
    case realSteps = 0x0B
    case experimental = 0x0C
    case cvaPPG = 0x0D
}

enum FeatureMode: UInt8 {
    case off = 0x00
    case automatic = 0x01
    case requested = 0x02
    case connectedLive = 0x03
}

enum FeatureSubscriptionMode: UInt8 {
    case off = 0x00
    case state = 0x01
    case latest = 0x02
}

// MARK: - Event tags (sensor data from ring)

enum EventTag: UInt8 {
    case ibi = 0x44
    case temperature = 0x46
    case accelerometer = 0x47
    case sleepPeriod = 0x48
    case sleepSummary = 0x49
    case ppgAmplitude = 0x4A
    case sleepPhase = 0x4B
    case sleepPhasesSummary = 0x4C
    case sleepMovement = 0x4F
    case activityInfo = 0x50
    case wearState = 0x53
    case recovery = 0x54
    case heartRate = 0x55
    case alert = 0x56
    case sleepSummaryV2 = 0x58
    case sleepPhaseV2 = 0x5A
    case hrvSummary = 0x5D
    case ppgRaw = 0x64
    case ppgPeaks = 0x63
    case ppgRawV2 = 0x68
    case sleepPeriodV2 = 0x6A
    case ppgAmplitudeV2 = 0x6E
    case spo2 = 0x6F
    case ppgAmplitudeV3 = 0x71
    case temperatureV2 = 0x75
    case steps = 0x7E
    case stepsV2 = 0x7F
}

// MARK: - Commands

struct OuraCommand {
    static let getFirmware = Data([0x08, 0x03, 0x00, 0x00, 0x00])
    static let getBattery = Data([0x0C, 0x00])
    static let getAuthNonce = Data([0x2F, 0x01, 0x2B])
    static let setNotification = Data([0x1C, 0x01, 0x3F])
    static let factoryReset = Data([0x1A, 0x00])

    static func setAuthKey(_ key: Data) -> Data {
        packet(tag: 0x24, payload: key)
    }

    static func authenticate(key: Data, nonce: Data) -> Data {
        let encrypted = aesECBEncryptPKCS7(data: nonce, key: key)
        return packet(tag: 0x2F, payload: Data([0x2D]) + encrypted)
    }

    static func syncTime(unixSeconds: UInt64, timezoneHalfHours: UInt8 = 0) -> Data {
        var payload = Data(count: 9)
        payload.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: unixSeconds.littleEndian, as: UInt64.self)
            buf[8] = timezoneHalfHours
        }
        return packet(tag: 0x12, payload: payload)
    }

    static func setFeatureMode(feature: FeatureID, mode: FeatureMode) -> Data {
        Data([0x2F, 0x03, 0x22, feature.rawValue, mode.rawValue])
    }

    static func setRingMode(_ mode: RingMode) -> Data {
        packet(tag: 0x31, payload: Data([mode.rawValue, 0x00, 0x00, 0x00]))
    }

    static func setBLEMode(_ mode: RingMode) -> Data {
        packet(tag: 0x16, payload: Data([mode.rawValue]))
    }

    static func getEvents(afterTimestamp: UInt32 = 0, maxEvents: UInt8 = 0xFF) -> Data {
        // open_oura: struct.pack("<IBi", timestamp, max_events, -1)
        var payload = Data(count: 9)
        payload.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: afterTimestamp.littleEndian, as: UInt32.self)
        }
        payload[4] = maxEvents
        // flags = -1 (0xFFFFFFFF) = all event types
        payload[5] = 0xFF
        payload[6] = 0xFF
        payload[7] = 0xFF
        payload[8] = 0xFF
        return packet(tag: 0x10, payload: payload)
    }

    static func getLatestReading(feature: FeatureID) -> Data {
        // Poll latest sensor value: 2f 02 24 [featureID]
        Data([0x2F, 0x02, 0x24, feature.rawValue])
    }

    static func getFeatureStatus(feature: FeatureID) -> Data {
        Data([0x2F, 0x02, 0x20, feature.rawValue])
    }

    static func setFeatureSubscription(feature: FeatureID, mode: FeatureSubscriptionMode) -> Data {
        Data([0x2F, 0x03, 0x26, feature.rawValue, mode.rawValue])
    }

    static func getProductInfo() -> Data {
        packet(tag: 0x18, payload: Data())
    }

    // MARK: - Helpers

    static func packet(tag: UInt8, payload: Data) -> Data {
        Data([tag, UInt8(payload.count)]) + payload
    }

    static func generateAuthKey() -> Data {
        var bytes = Data(count: 16)
        bytes.withUnsafeMutableBytes { buf in
            _ = SecRandomCopyBytes(kSecRandomDefault, 16, buf.baseAddress!)
        }
        return bytes
    }

    static func aesECBEncryptPKCS7(data: Data, key: Data) -> Data {
        let blockSize = 16
        var padded = data
        let paddingLength = blockSize - (padded.count % blockSize)
        padded.append(contentsOf: [UInt8](repeating: UInt8(paddingLength), count: paddingLength))

        var encrypted = Data(count: padded.count)
        padded.withUnsafeBytes { plainBuf in
            key.withUnsafeBytes { keyBuf in
                encrypted.withUnsafeMutableBytes { outBuf in
                    var numBytesEncrypted: size_t = 0
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuf.baseAddress!, keyBuf.count,
                        nil,
                        plainBuf.baseAddress!, plainBuf.count,
                        outBuf.baseAddress!, outBuf.count,
                        &numBytesEncrypted
                    )
                }
            }
        }
        return encrypted
    }
}

// MARK: - Packet parsing

struct ParsedPacket {
    let tag: UInt8
    let length: UInt8
    let payload: Data
    let raw: Data

    var firmwareVersion: String? {
        guard tag == 0x09, payload.count >= 18 else { return nil }
        return "\(payload[3]).\(payload[4]).\(payload[5])"
    }

    var apiVersion: String? {
        guard tag == 0x09, payload.count >= 18 else { return nil }
        return "\(payload[0]).\(payload[1]).\(payload[2])"
    }

    var bleMac: String? {
        guard tag == 0x09, payload.count >= 18 else { return nil }
        return (12..<18).reversed().map { String(format: "%02x", payload[$0]) }.joined(separator: ":")
    }

    var batteryPercent: UInt8? {
        guard tag == 0x0D, payload.count >= 1 else { return nil }
        return payload[0]
    }

    var chargingProgress: UInt8? {
        guard tag == 0x0D, payload.count >= 2 else { return nil }
        return payload[1]
    }

    var isCharging: Bool {
        (chargingProgress ?? 0) > 0
    }

    var authNonce: Data? {
        guard tag == 0x2F, payload.count >= 2, payload[0] == 0x2C else { return nil }
        return payload.subdata(in: 1..<payload.count)
    }

    var authResult: AuthResult? {
        guard tag == 0x2F, payload.count >= 2,
              payload[0] == 0x2E || payload[0] == 0x2F else { return nil }
        return AuthResult(rawValue: payload[1])
    }

    var setAuthKeyStatus: UInt8? {
        guard tag == 0x25, payload.count >= 1 else { return nil }
        return payload[0]
    }

    var notificationStatus: UInt8? {
        guard tag == 0x1D, payload.count >= 1 else { return nil }
        return payload[0]
    }

    // Feature status response: 2f [len] 21 [featureID] [mode] [status] [state] [subscription]
    var featureStatus: (featureID: UInt8, mode: UInt8, status: UInt8, state: UInt8)? {
        guard tag == 0x2F, payload.count >= 5, payload[0] == 0x21 else { return nil }
        return (featureID: payload[1], mode: payload[2], status: payload[3], state: payload[4])
    }

    // Latest reading response: 2f [len] 25 [featureID] [result] [data...]
    var latestReading: (featureID: UInt8, result: UInt8, data: Data)? {
        guard tag == 0x2F, payload.count >= 3, payload[0] == 0x25 else { return nil }
        let readingData = payload.count > 3 ? payload.subdata(in: 3..<payload.count) : Data()
        return (featureID: payload[1], result: payload[2], data: readingData)
    }

    // Feature subscription response: 2f [len] 27 [featureID] [result]
    var subscriptionResult: (featureID: UInt8, result: UInt8)? {
        guard tag == 0x2F, payload.count >= 3, payload[0] == 0x27 else { return nil }
        return (featureID: payload[1], result: payload[2])
    }

    // Live HR notification: 2f [len] 28 [featureID=02] ... [ibi_lo] [ibi_hi|validity]
    // From open_oura: frame[8]=lo, frame[9]=hi; ibi = ((hi & 0x0f) << 8) | lo; validity = (hi >> 4) & 0x0f
    var liveHR: (ibiMs: UInt16, bpm: Double)? {
        guard tag == 0x2F, payload.count >= 8, payload[0] == 0x28, payload[1] == 0x02 else { return nil }
        let lo = payload[6]
        let hi = payload[7]
        let ibi = UInt16(hi & 0x0F) << 8 | UInt16(lo)
        let validity = (hi >> 4) & 0x0F
        guard validity == 1, ibi > 200, ibi < 2000 else { return nil }
        return (ibiMs: ibi, bpm: 60000.0 / Double(ibi))
    }

    // Ring mode response: 32 04 [mode] 00 00 00
    var ringModeResult: UInt8? {
        guard tag == 0x32, payload.count >= 1 else { return nil }
        return payload[0]
    }
}

extension ParsedPacket {
    static func parse(_ data: Data) -> ParsedPacket? {
        guard data.count >= 2 else { return nil }
        let tag = data[0]
        let length = data[1]
        let payload = data.count > 2 ? data.subdata(in: 2..<data.count) : Data()
        return ParsedPacket(tag: tag, length: length, payload: payload, raw: data)
    }
}

// MARK: - Sensor event parsing

struct SensorEvent {
    let tag: UInt8
    let deviceTimestamp: UInt32
    let payload: Data

    static func parseEvents(from data: Data) -> [SensorEvent] {
        var events: [SensorEvent] = []
        var offset = 0
        while offset + 2 <= data.count {
            let tag = data[offset]
            let length = Int(data[offset + 1])

            // Validate: need enough data for the declared length
            guard length > 0, offset + 2 + length <= data.count else { break }

            if length >= 4 {
                // Standard event format: [tag][length][timestamp(4)][payload(length-4)]
                let timestamp = data.subdata(in: (offset + 2)..<(offset + 6))
                    .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
                let eventPayload = length > 4
                    ? data.subdata(in: (offset + 6)..<(offset + 2 + length))
                    : Data()
                events.append(SensorEvent(tag: tag, deviceTimestamp: timestamp, payload: eventPayload))
            } else {
                // Short event (no timestamp): use payload directly with timestamp 0
                let eventPayload = data.subdata(in: (offset + 2)..<(offset + 2 + length))
                events.append(SensorEvent(tag: tag, deviceTimestamp: 0, payload: eventPayload))
            }

            offset += 2 + length
        }
        return events
    }
}

// MARK: - Parsed health values from sensor events

struct IBIReading {
    let timestamp: Date
    let intervalMs: UInt16
    var bpm: Double { 60000.0 / Double(intervalMs) }
}

struct TemperatureReading {
    let timestamp: Date
    let celsiusTenths: Int16
    var celsius: Double { Double(celsiusTenths) / 10.0 }
}

struct SpO2Reading {
    let timestamp: Date
    let percent: UInt8
}

struct AccelerometerReading {
    let timestamp: Date
    let x: Int16
    let y: Int16
    let z: Int16
}

struct SleepPhaseReading {
    let timestamp: Date
    let phase: SleepPhase
}

enum SleepPhase: UInt8 {
    case awake = 0
    case light = 1
    case deep = 2
    case rem = 3
}

struct StepReading {
    let timestamp: Date
    let count: UInt16
}

struct HRVReading {
    let timestamp: Date
    let rmssd: Double
}

extension SensorEvent {
    private func eventDate(ringBootTime: Date) -> Date {
        if deviceTimestamp == 0 { return Date() }
        // If timestamp looks like a unix timestamp (> 2020-01-01), use it directly
        if deviceTimestamp > 1_577_836_800 {
            return Date(timeIntervalSince1970: Double(deviceTimestamp))
        }
        return ringBootTime.addingTimeInterval(Double(deviceTimestamp))
    }

    func toIBI(ringBootTime: Date) -> IBIReading? {
        guard tag == EventTag.ibi.rawValue, payload.count >= 2 else { return nil }
        let ms = payload.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        guard ms > 200 && ms < 2000 else { return nil }
        return IBIReading(
            timestamp: eventDate(ringBootTime: ringBootTime),
            intervalMs: ms
        )
    }

    func toTemperature(ringBootTime: Date) -> TemperatureReading? {
        guard tag == EventTag.temperature.rawValue || tag == EventTag.temperatureV2.rawValue,
              payload.count >= 2 else { return nil }
        let tenths = payload.withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        return TemperatureReading(
            timestamp: eventDate(ringBootTime: ringBootTime),
            celsiusTenths: tenths
        )
    }

    func toSpO2(ringBootTime: Date) -> SpO2Reading? {
        guard tag == EventTag.spo2.rawValue, payload.count >= 1 else { return nil }
        let pct = payload[0]
        guard pct >= 70 && pct <= 100 else { return nil }
        return SpO2Reading(
            timestamp: eventDate(ringBootTime: ringBootTime),
            percent: pct
        )
    }

    func toAccelerometer(ringBootTime: Date) -> AccelerometerReading? {
        guard tag == EventTag.accelerometer.rawValue, payload.count >= 6 else { return nil }
        return payload.withUnsafeBytes { buf in
            AccelerometerReading(
                timestamp: eventDate(ringBootTime: ringBootTime),
                x: buf.load(fromByteOffset: 0, as: Int16.self).littleEndian,
                y: buf.load(fromByteOffset: 2, as: Int16.self).littleEndian,
                z: buf.load(fromByteOffset: 4, as: Int16.self).littleEndian
            )
        }
    }

    func toSleepPhase(ringBootTime: Date) -> SleepPhaseReading? {
        guard tag == EventTag.sleepPhase.rawValue || tag == EventTag.sleepPhaseV2.rawValue,
              payload.count >= 1 else { return nil }
        guard let phase = SleepPhase(rawValue: payload[0]) else { return nil }
        return SleepPhaseReading(
            timestamp: eventDate(ringBootTime: ringBootTime),
            phase: phase
        )
    }

    func toSteps(ringBootTime: Date) -> StepReading? {
        guard tag == EventTag.steps.rawValue || tag == EventTag.stepsV2.rawValue,
              payload.count >= 2 else { return nil }
        let count = payload.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        return StepReading(
            timestamp: eventDate(ringBootTime: ringBootTime),
            count: count
        )
    }
}
