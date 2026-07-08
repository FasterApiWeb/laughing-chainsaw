import Foundation
@preconcurrency import CoreBluetooth
import os

private let log = Logger(subsystem: "com.librering.app", category: "BLE")

// MARK: - Oura BLE constants

enum OuraBLE: Sendable {
    static nonisolated(unsafe) let primaryServiceUUID = CBUUID(string: "98ed0001-a541-11e4-b6a0-0002a5d5c51b")
    static nonisolated(unsafe) let auxServiceUUID = CBUUID(string: "00060000-f8ce-11e4-abf4-0002a5d5c51b")

    static nonisolated(unsafe) let cmdCharUUID = CBUUID(string: "98ed0002-a541-11e4-b6a0-0002a5d5c51b")
    static nonisolated(unsafe) let dataCharUUID = CBUUID(string: "98ed0003-a541-11e4-b6a0-0002a5d5c51b")
    static nonisolated(unsafe) let extDataCharUUID = CBUUID(string: "98ed0004-a541-11e4-b6a0-0002a5d5c51b")
    static nonisolated(unsafe) let notifyACharUUID = CBUUID(string: "98ed0005-a541-11e4-b6a0-0002a5d5c51b")
    static nonisolated(unsafe) let notifyBCharUUID = CBUUID(string: "98ed0006-a541-11e4-b6a0-0002a5d5c51b")

    static let manufacturerID: UInt16 = 0x02B2
}

// MARK: - Connection state

enum RingConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case authenticating
    case pairing
    case connected
    case error(String)
}

// MARK: - Discovered ring info (no CBPeripheral — that stays in the manager)

struct DiscoveredRingInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

// MARK: - Ring info

struct RingInfo: Equatable {
    var firmwareVersion: String = ""
    var apiVersion: String = ""
    var bleMac: String = ""
    var batteryPercent: UInt8 = 0
    var isCharging: Bool = false
    var name: String = ""
}

// MARK: - BLEManager
// Runs entirely on the main queue — no actor, no Task hopping.
// CBCentralManager is created with queue: .main so all callbacks are on main.

final class BLEManager: NSObject, ObservableObject {
    @Published var connectionState: RingConnectionState = .disconnected
    @Published var discoveredRings: [DiscoveredRingInfo] = []
    @Published var ringInfo = RingInfo()
    @Published var lastSyncDate: Date?
    @Published var pairingMessage: String = ""
    @Published var syncStatus: String = ""

    @Published var latestHeartRate: Double = 0
    @Published var latestSpO2: UInt8 = 0
    @Published var latestTemperature: Double = 0
    @Published var latestHRV: Double = 0
    @Published var latestSteps: UInt16 = 0
    @Published var ibiReadings: [IBIReading] = []
    @Published var sleepPhases: [SleepPhaseReading] = []
    @Published var temperatureReadings: [TemperatureReading] = []
    @Published var spo2Readings: [SpO2Reading] = []
    @Published var stepReadings: [StepReading] = []

    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var cmdCharacteristic: CBCharacteristic?
    private var dataCharacteristic: CBCharacteristic?
    private var gattReady = false

    private var authKey: Data?
    private var responseBuffer: [Data] = []
    private var responseTimer: Timer?
    private var responseCallback: (([Data]) -> Void)?
    private var ringBootTime = Date()
    private var autoSyncTimer: Timer?

    private let keychain = KeychainStore()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionState = .error("Bluetooth is not available")
            return
        }
        discoveredRings.removeAll()
        discoveredPeripherals.removeAll()
        connectionState = .scanning
        centralManager.scanForPeripherals(
            withServices: [OuraBLE.primaryServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log.info("Started scanning for Oura rings")
    }

    func stopScanning() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(ringID: UUID) {
        guard let peripheral = discoveredPeripherals[ringID] else { return }
        stopScanning()
        connectionState = .connecting
        pairingMessage = ""
        gattReady = false
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        log.info("Connecting to \(peripheral.name ?? "ring")")
    }

    func disconnect() {
        if let peripheral = connectedPeripheral, let cmd = cmdCharacteristic {
            let unsubHR = OuraCommand.setFeatureSubscription(feature: .daytimeHR, mode: .off)
            peripheral.writeValue(unsubHR, for: cmd, type: .withResponse)
            let unsubSpO2 = OuraCommand.setFeatureSubscription(feature: .spo2, mode: .off)
            peripheral.writeValue(unsubSpO2, for: cmd, type: .withResponse)
            let restoreHR = OuraCommand.setFeatureMode(feature: .daytimeHR, mode: .automatic)
            peripheral.writeValue(restoreHR, for: cmd, type: .withResponse)
            let normalMode = OuraCommand.setRingMode(.normal)
            peripheral.writeValue(normalMode, for: cmd, type: .withResponse)
            let normalBLE = OuraCommand.setBLEMode(.normal)
            peripheral.writeValue(normalBLE, for: cmd, type: .withResponse)
            log.info("Restored subscriptions, daytimeHR, ring mode, and BLE mode to normal")
        }
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        resetState()
    }

    func factoryReset() {
        guard cmdCharacteristic != nil else {
            connectionState = .error("Not connected — connect to ring first")
            return
        }

        sendCommand(OuraCommand.factoryReset, timeout: 5.0) { [weak self] responses in
            guard let self else { return }
            for resp in responses {
                if let packet = ParsedPacket.parse(resp) {
                    log.info("Factory reset response: tag=0x\(String(format: "%02x", packet.tag))")
                }
            }
            if let peripheralID = self.connectedPeripheral?.identifier.uuidString {
                self.keychain.deleteAuthKey(for: peripheralID)
            }
            self.authKey = nil
            self.pairingMessage = "Factory reset sent. Put ring on charger, wait 30 seconds, then reconnect."
            self.disconnect()
        }
    }

    func importKey(_ hexString: String) -> Bool {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 32,
              let key = Data(hexString: cleaned) else { return false }
        authKey = key
        if let peripheralID = connectedPeripheral?.identifier.uuidString {
            keychain.saveAuthKey(key, for: peripheralID)
        }
        return true
    }

    func triggerSync() {
        guard connectionState == .connected else { return }
        syncAllData()
    }

    // MARK: - Command send (callback-based, no async/continuations)
    // Matches Python transact(): only DATA char responses are collected,
    // and we fire early once a response has arrived and no new data for 300ms.

    private var responseIdleTimer: Timer?
    private var responseIdleInterval: TimeInterval = 0.3

    private func sendCommand(_ command: Data, timeout: TimeInterval = 3.0, idleGap: TimeInterval = 0.3, completion: @escaping ([Data]) -> Void) {
        guard let char = cmdCharacteristic, let peripheral = connectedPeripheral else {
            log.error("sendCommand: no char or peripheral")
            completion([])
            return
        }

        responseTimer?.invalidate()
        responseIdleTimer?.invalidate()
        responseBuffer.removeAll()
        responseCallback = completion
        responseIdleInterval = idleGap

        let cmdHex = command.prefix(min(8, command.count)).map { String(format: "%02x", $0) }.joined(separator: " ")
        log.info("TX cmd: \(cmdHex) (timeout=\(timeout)s idle=\(idleGap)s)")

        peripheral.writeValue(command, for: char, type: .withResponse)

        responseTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.responseIdleTimer?.invalidate()
            self.responseIdleTimer = nil
            let buffer = self.responseBuffer
            let cb = self.responseCallback
            self.responseCallback = nil
            self.responseTimer = nil
            log.info("RX timeout: \(buffer.count) packets collected")
            cb?(buffer)
        }
    }

    private func onDataCharResponse() {
        responseIdleTimer?.invalidate()
        guard responseCallback != nil else { return }
        responseIdleTimer = Timer.scheduledTimer(withTimeInterval: responseIdleInterval, repeats: false) { [weak self] _ in
            guard let self, let cb = self.responseCallback else { return }
            self.responseTimer?.invalidate()
            self.responseTimer = nil
            self.responseIdleTimer = nil
            self.responseCallback = nil
            let buffer = self.responseBuffer
            log.info("RX idle: \(buffer.count) packets collected (fast path)")
            cb(buffer)
        }
    }

    // MARK: - Auth + pairing flow

    private func onGATTReady() {
        if loadSavedKey() {
            log.info("Found saved auth key, authenticating...")
            connectionState = .authenticating
            syncStatus = "Authenticating with saved key..."
            attemptAuth { [weak self] success in
                guard let self else { return }
                if success {
                    self.connectionState = .connected
                    self.syncStatus = "Authenticated — starting sync..."
                    self.syncAllData()
                } else {
                    log.info("Saved key rejected, clearing and trying fresh pair")
                    self.syncStatus = "Saved key rejected — re-pairing..."
                    if let pid = self.connectedPeripheral?.identifier.uuidString {
                        self.keychain.deleteAuthKey(for: pid)
                    }
                    self.authKey = nil
                    self.attemptFreshPairing()
                }
            }
        } else {
            log.info("No saved key, attempting fresh pairing")
            syncStatus = "No auth key — pairing..."
            attemptFreshPairing()
        }
    }

    private func attemptFreshPairing() {
        log.info("No valid auth key, attempting fresh pairing...")
        connectionState = .pairing
        pairingMessage = "Pairing with ring..."

        let newKey = OuraCommand.generateAuthKey()
        let setKeyCmd = OuraCommand.setAuthKey(newKey)

        sendCommand(setKeyCmd, timeout: 5.0) { [weak self] responses in
            guard let self else { return }

            for resp in responses {
                guard let packet = ParsedPacket.parse(resp) else { continue }

                if packet.setAuthKeyStatus == 0x00 {
                    self.authKey = newKey
                    if let peripheralID = self.connectedPeripheral?.identifier.uuidString {
                        self.keychain.saveAuthKey(newKey, for: peripheralID)
                    }
                    log.info("Pairing successful, new key installed")
                    self.pairingMessage = "Paired! Authenticating..."
                    self.connectionState = .authenticating

                    self.attemptAuth { success in
                        if success {
                            self.connectionState = .connected
                            self.pairingMessage = ""
                            self.syncAllData()
                        } else {
                            self.connectionState = .error("Paired but auth failed — try reconnecting")
                        }
                    }
                    return
                }

                if packet.authResult == .inFactoryReset {
                    self.pairingMessage = "Ring is resetting. Wait 30 seconds, then reconnect."
                    self.connectionState = .error("Ring is in factory reset — wait and reconnect")
                    return
                }

                if packet.authResult == .notOriginalDevice {
                    self.pairingMessage = "Ring is paired to another device. Factory reset it first, or import the existing key."
                    self.connectionState = .error("Ring already paired — factory reset needed")
                    return
                }
            }

            // SetAuthKey didn't return success — ring already has a key
            self.sendCommand(OuraCommand.getAuthNonce, timeout: 3.0) { nonceResp in
                let hasNonce = nonceResp.contains { ParsedPacket.parse($0)?.authNonce != nil }

                if hasNonce {
                    self.pairingMessage = "Ring is already paired to another device. Factory reset the ring first:\n\n1. Open Oura app → Settings → Reset\n   OR use the Factory Reset button below\n2. Place ring on charger for 30 seconds\n3. Come back and reconnect"
                    self.connectionState = .error("Ring already paired — factory reset needed")
                } else {
                    self.pairingMessage = "Could not communicate with ring. Make sure it's charged and nearby."
                    self.connectionState = .error("No response from ring")
                }
            }
        }
    }

    private func attemptAuth(completion: @escaping (Bool) -> Void) {
        guard let key = authKey else {
            log.error("attemptAuth: no auth key available")
            syncStatus = "No auth key"
            completion(false)
            return
        }
        log.info("attemptAuth: key=\(key.prefix(4).map { String(format: "%02x", $0) }.joined())... sending GetAuthNonce")
        syncStatus = "Requesting auth nonce..."

        sendCommand(OuraCommand.getAuthNonce) { [weak self] nonceResponses in
            guard let self else { completion(false); return }
            log.info("GetAuthNonce returned \(nonceResponses.count) responses")

            var nonce: Data?
            for resp in nonceResponses {
                if let packet = ParsedPacket.parse(resp) {
                    log.info("  nonce resp tag=0x\(String(format: "%02x", packet.tag)) payload=\(packet.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                    if let n = packet.authNonce {
                        nonce = n
                        break
                    }
                }
            }

            guard let nonce else {
                log.error("Ring did not return auth nonce")
                self.syncStatus = "Auth failed — no nonce from ring"
                completion(false)
                return
            }
            log.info("Got nonce: \(nonce.map { String(format: "%02x", $0) }.joined())")
            self.syncStatus = "Authenticating..."

            let authCmd = OuraCommand.authenticate(key: key, nonce: nonce)
            self.sendCommand(authCmd) { authResponses in
                log.info("Authenticate returned \(authResponses.count) responses")
                for resp in authResponses {
                    if let packet = ParsedPacket.parse(resp) {
                        log.info("  auth resp tag=0x\(String(format: "%02x", packet.tag)) payload=\(packet.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                        if let result = packet.authResult {
                            switch result {
                            case .success:
                                log.info("Authentication successful")
                                completion(true)
                                return
                            case .authenticationError:
                                log.error("Auth REJECTED — wrong key")
                                self.syncStatus = "Wrong auth key — re-pair or import correct key"
                            case .inFactoryReset:
                                log.error("Ring is in factory reset mode")
                                self.syncStatus = "Ring resetting — wait 30s and reconnect"
                            case .notOriginalDevice:
                                log.error("Ring paired to another device")
                                self.syncStatus = "Ring paired elsewhere — factory reset needed"
                            }
                        }
                    }
                }
                log.error("Authentication failed — no success response")
                completion(false)
            }
        }
    }

    private func loadSavedKey() -> Bool {
        guard let peripheralID = connectedPeripheral?.identifier.uuidString,
              let saved = keychain.loadAuthKey(for: peripheralID) else { return false }
        authKey = saved
        return true
    }

    // MARK: - Sync

    @Published var isSyncing = false

    private func syncAllData() {
        guard !isSyncing else {
            log.info("Sync already in progress, skipping")
            return
        }
        guard connectedPeripheral != nil, cmdCharacteristic != nil else {
            log.error("Cannot sync: no peripheral or cmd characteristic")
            syncStatus = "Not ready — reconnect ring"
            return
        }
        isSyncing = true
        syncStatus = "Enabling notifications..."
        log.info("Starting sync...")

        // Step 1: Enable notifications FIRST (matches Python listen_oura.py flow)
        sendCommand(OuraCommand.setNotification, timeout: 2.0) { [weak self] notifResp in
            guard let self else { return }
            for resp in notifResp {
                if let p = ParsedPacket.parse(resp) {
                    log.info("Notification response: tag=0x\(String(format: "%02x", p.tag)) status=\(p.notificationStatus.map { String($0) } ?? "nil")")
                }
            }

            // Step 2: Sync time
            self.syncStatus = "Syncing time..."
            let now = Date()
            let unixNow = UInt64(now.timeIntervalSince1970)
            let tzOffset = UInt8(max(0, TimeZone.current.secondsFromGMT() / 1800))
            self.sendCommand(OuraCommand.syncTime(unixSeconds: unixNow, timezoneHalfHours: tzOffset), timeout: 3.0) { [weak self] _ in
                guard let self else { return }
                log.info("Time synced")
                self.syncStatus = "Reading device info..."

                // Step 3: Get device info (firmware + battery)
                self.sendCommand(OuraCommand.getFirmware, timeout: 3.0) { [weak self] fwResp in
                    guard let self else { return }
                    for resp in fwResp {
                        if let packet = ParsedPacket.parse(resp) {
                            if let fw = packet.firmwareVersion { self.ringInfo.firmwareVersion = fw }
                            if let api = packet.apiVersion { self.ringInfo.apiVersion = api }
                            if let mac = packet.bleMac { self.ringInfo.bleMac = mac }
                        }
                    }

                    self.sendCommand(OuraCommand.getBattery, timeout: 3.0) { [weak self] batResp in
                        guard let self else { return }
                        for resp in batResp {
                            if let packet = ParsedPacket.parse(resp) {
                                if let bat = packet.batteryPercent { self.ringInfo.batteryPercent = bat }
                                if packet.tag == 0x0D { self.ringInfo.isCharging = packet.isCharging }
                            }
                        }
                        self.ringInfo.name = self.connectedPeripheral?.name ?? "Oura Ring"
                        log.info("Device info: fw=\(self.ringInfo.firmwareVersion) bat=\(self.ringInfo.batteryPercent)% charging=\(self.ringInfo.isCharging)")

                        if self.ringInfo.isCharging {
                            log.warning("⚠️ Ring is ON CHARGER — PPG sensor cannot measure. Take ring off charger and put on finger.")
                            self.syncStatus = "Ring is charging — put on finger for heart rate"
                        }

                        // Step 4: Enable subscription-gated features
                        self.enableFeatures()
                    }
                }
            }
        }
    }

    private func enableFeatures() {
        syncStatus = "Enabling features..."
        // connectedLive (0x03) = ring pushes live IBI notifications (from open_oura live-hr)
        let features: [(FeatureID, FeatureMode, String)] = [
            (.researchData, .automatic, "researchData"),
            (.bleMode, .automatic, "bleMode"),
            (.realSteps, .automatic, "realSteps"),
            (.restingHR, .automatic, "restingHR"),
            (.daytimeHR, .connectedLive, "daytimeHR"),
            (.spo2, .requested, "SpO2"),
        ]

        enableFeatureSequence(features, index: 0) { [weak self] in
            guard let self else { return }
            self.syncStatus = "Setting measurement mode..."
            self.sendCommand(OuraCommand.setRingMode(.fastHR), timeout: 3.0) { [weak self] modeResp in
                guard let self else { return }
                for resp in modeResp {
                    if let p = ParsedPacket.parse(resp) {
                        if let mode = p.ringModeResult {
                            log.info("Ring mode set to: \(mode)")
                        } else {
                            log.info("setRingMode response: tag=0x\(String(format: "%02x", p.tag)) payload=\(p.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                        }
                    }
                }
                self.sendCommand(OuraCommand.setBLEMode(.fastHR), timeout: 2.0) { [weak self] _ in
                    guard let self else { return }
                    log.info("BLE mode set to fastHR")
                    self.syncStatus = "Subscribing to sensors..."
                    self.enableSubscriptions()
                }
            }
        }
    }

    private func enableSubscriptions() {
        let subs: [(FeatureID, FeatureSubscriptionMode, String)] = [
            (.daytimeHR, .latest, "daytimeHR"),
            (.spo2, .latest, "SpO2"),
        ]
        enableSubscriptionSequence(subs, index: 0) { [weak self] in
            self?.requestEvents()
        }
    }

    private func enableSubscriptionSequence(_ subs: [(FeatureID, FeatureSubscriptionMode, String)], index: Int, completion: @escaping () -> Void) {
        guard index < subs.count else { completion(); return }
        let (feature, mode, name) = subs[index]
        let cmd = OuraCommand.setFeatureSubscription(feature: feature, mode: mode)
        sendCommand(cmd, timeout: 2.0) { [weak self] responses in
            for resp in responses {
                if let p = ParsedPacket.parse(resp) {
                    if let sub = p.subscriptionResult {
                        log.info("Subscription \(name): result=\(sub.result)")
                    } else {
                        log.info("Subscription \(name): tag=0x\(String(format: "%02x", p.tag)) payload=\(p.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                    }
                }
            }
            self?.enableSubscriptionSequence(subs, index: index + 1, completion: completion)
        }
    }

    private func enableFeatureSequence(_ features: [(FeatureID, FeatureMode, String)], index: Int, completion: @escaping () -> Void) {
        guard index < features.count else { completion(); return }
        let (feature, mode, name) = features[index]
        let cmd = OuraCommand.setFeatureMode(feature: feature, mode: mode)
        sendCommand(cmd, timeout: 2.0) { [weak self] responses in
            for resp in responses {
                if let p = ParsedPacket.parse(resp) {
                    log.info("Feature \(name)=\(mode.rawValue): tag=0x\(String(format: "%02x", p.tag)) payload=\(p.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                }
            }
            self?.enableFeatureSequence(features, index: index + 1, completion: completion)
        }
    }

    private func requestEvents() {
        syncStatus = "Reading sensor data..."
        let lastSync = UInt32(lastSyncDate?.timeIntervalSince1970 ?? 0)
        log.info("Requesting events after timestamp \(lastSync)")

        sendCommand(OuraCommand.getEvents(afterTimestamp: lastSync), timeout: 15.0, idleGap: 2.0) { [weak self] responses in
            guard let self else { return }
            log.info("getEvents returned \(responses.count) packets")

            var totalParsed = 0
            for resp in responses {
                let events = SensorEvent.parseEvents(from: resp)
                if !events.isEmpty {
                    self.processEvents(events)
                    totalParsed += events.count
                }
            }

            log.info("Sync done: parsed=\(totalParsed) HR:\(self.ibiReadings.count) SpO2:\(self.spo2Readings.count) temp:\(self.temperatureReadings.count) sleep:\(self.sleepPhases.count) steps:\(self.stepReadings.count)")
            self.syncStatus = totalParsed > 0
                ? "Synced \(totalParsed) readings"
                : "Connected — listening for live data"
            self.lastSyncDate = Date()
            self.isSyncing = false
            self.persistData()
            self.startLivePolling()

            Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
                self?.syncStatus = ""
            }
        }
    }

    // MARK: - Live sensor polling

    private var isPolling = false

    private func startLivePolling() {
        autoSyncTimer?.invalidate()
        log.info("Starting live sensor polling (every 5s)")
        syncStatus = "Live — polling sensors..."
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.connectionState == .connected, !self.isPolling else { return }
            self.pollLatestReadings()
        }
        // First poll immediately
        pollLatestReadings()
    }

    private func pollLatestReadings() {
        guard !isPolling else { return }
        isPolling = true

        sendCommand(OuraCommand.getFeatureStatus(feature: .daytimeHR), timeout: 2.0) { [weak self] statusResp in
            guard let self else { return }
            for resp in statusResp {
                if let p = ParsedPacket.parse(resp), let status = p.featureStatus {
                    let stateNames = ["idle", "scanning", "measuring", "postprocessing"]
                    let stateName = Int(status.state) < stateNames.count ? stateNames[Int(status.state)] : "?\(status.state)"
                    let statusName: String
                    switch status.status {
                    case 0: statusName = "off"
                    case 1: statusName = "on"
                    case 2: statusName = "searching"
                    case 3: statusName = "no_ppg"
                    case 4: statusName = "cold_fingers"
                    case 5: statusName = "movement"
                    case 6: statusName = "identifying"
                    default: statusName = status.status & 0x01 != 0 ? "on+0x\(String(format: "%02x", status.status))" : "?\(status.status)"
                    }
                    log.info("HR status: mode=\(status.mode) status=\(statusName) state=\(stateName)")
                    if status.status == 0 && self.ringInfo.isCharging {
                        log.warning("PPG off because ring is on charger — readings will be zero until ring is on finger")
                    }
                }
            }

            // Poll latest HR
            self.sendCommand(OuraCommand.getLatestReading(feature: .daytimeHR), timeout: 2.0) { [weak self] hrResp in
                guard let self else { return }
                for resp in hrResp {
                    if let p = ParsedPacket.parse(resp), let reading = p.latestReading {
                        log.info("Latest HR: feature=\(reading.featureID) result=\(reading.result) data=\(reading.data.map { String(format: "%02x", $0) }.joined(separator: " "))")
                        self.parseLatestHR(reading.data)
                    }
                }

                // Poll latest SpO2
                self.sendCommand(OuraCommand.getLatestReading(feature: .spo2), timeout: 2.0) { [weak self] spo2Resp in
                    guard let self else { return }
                    for resp in spo2Resp {
                        if let p = ParsedPacket.parse(resp), let reading = p.latestReading {
                            log.info("Latest SpO2: feature=\(reading.featureID) result=\(reading.result) data=\(reading.data.map { String(format: "%02x", $0) }.joined(separator: " "))")
                            self.parseLatestSpO2(reading.data)
                        }
                    }
                    self.isPolling = false
                }
            }
        }
    }

    private func parseLatestHR(_ data: Data) {
        // open_oura: for daytimeHR, IBI is at payload offset 7 from ext_tag (= our data offset 4)
        guard data.count >= 6 else { return }
        let ibi = UInt16(data[4]) | (UInt16(data[5]) << 8)
        guard ibi > 200, ibi < 2000 else { return }
        let bpm = 60000.0 / Double(ibi)
        guard bpm > 30, bpm < 250 else { return }
        latestHeartRate = bpm
        ibiReadings.append(IBIReading(timestamp: Date(), intervalMs: ibi))
        log.info("Latest HR: \(Int(bpm)) BPM (IBI \(ibi)ms)")
    }

    private func parseLatestSpO2(_ data: Data) {
        // open_oura: SpO2 percent at their data[3] (= our data[7]), bpm at their data[4] (= our data[8])
        if data.count > 7 {
            let pct = data[7]
            if pct >= 70 && pct <= 100 {
                latestSpO2 = pct
                spo2Readings.append(SpO2Reading(timestamp: Date(), percent: pct))
                log.info("Latest SpO2: \(pct)%")
            }
        }
        if data.count > 8 {
            let bpm = data[8]
            if bpm > 30 && bpm < 250 && latestHeartRate == 0 {
                latestHeartRate = Double(bpm)
                log.info("SpO2 HR: \(bpm) BPM")
            }
        }
    }

    private func processEvents(_ events: [SensorEvent]) {
        for event in events {
            log.info("Event tag=0x\(String(format: "%02x", event.tag)) ts=\(event.deviceTimestamp) payload=\(event.payload.count)B: \(event.payload.prefix(min(8, event.payload.count)).map { String(format: "%02x", $0) }.joined(separator: " "))")

            var matched = false
            if let ibi = event.toIBI(ringBootTime: ringBootTime) {
                ibiReadings.append(ibi)
                latestHeartRate = ibi.bpm
                matched = true
            }
            if let temp = event.toTemperature(ringBootTime: ringBootTime) {
                temperatureReadings.append(temp)
                latestTemperature = temp.celsius
                matched = true
            }
            if let spo2 = event.toSpO2(ringBootTime: ringBootTime) {
                spo2Readings.append(spo2)
                latestSpO2 = spo2.percent
                matched = true
            }
            if let sleep = event.toSleepPhase(ringBootTime: ringBootTime) {
                sleepPhases.append(sleep)
                matched = true
            }
            if let steps = event.toSteps(ringBootTime: ringBootTime) {
                stepReadings.append(steps)
                latestSteps = steps.count
                matched = true
            }

            // Handle heart rate event (0x55) — contains BPM directly
            if event.tag == EventTag.heartRate.rawValue && event.payload.count >= 1 {
                let bpm = Double(event.payload[0])
                if bpm > 30 && bpm < 250 {
                    let reading = IBIReading(timestamp: Date(), intervalMs: UInt16(60000.0 / bpm))
                    ibiReadings.append(reading)
                    latestHeartRate = bpm
                    matched = true
                }
            }

            if !matched {
                log.info("Unmatched event tag=0x\(String(format: "%02x", event.tag)) payload=\(event.payload.prefix(min(8, event.payload.count)).map { String(format: "%02x", $0) }.joined(separator: " "))")
            }
        }

        if ibiReadings.count >= 10 {
            let recent = ibiReadings.suffix(30)
            latestHRV = HRVAnalysis.rmssd(from: recent.map { Double($0.intervalMs) })
        }
    }

    private func persistData() {
        let store = LocalStore.shared
        store.insertHeartRate(ibiReadings)
        store.insertSpO2(spo2Readings)
        store.insertTemperature(temperatureReadings)
        store.insertSleepPhases(sleepPhases)
        store.insertSteps(stepReadings)

        // Update baselines
        if latestHRV > 0 {
            let prev = store.loadBaseline(metric: "hrv")
            let updated = PersonalBaseline.compute(currentValue: latestHRV, previousBaseline: prev)
            store.saveBaseline(updated, metric: "hrv")
        }
        if latestHeartRate > 0 {
            let prev = store.loadBaseline(metric: "resting_hr")
            let updated = PersonalBaseline.compute(currentValue: latestHeartRate, previousBaseline: prev)
            store.saveBaseline(updated, metric: "resting_hr")
        }
        if latestTemperature > 0 {
            let prev = store.loadBaseline(metric: "temperature")
            let updated = PersonalBaseline.compute(currentValue: latestTemperature, previousBaseline: prev)
            store.saveBaseline(updated, metric: "temperature")
        }

        // Save daily summary
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())

        let sleepScore = SleepScoring.analyze(phases: sleepPhases)?.total ?? 0
        let totalSteps = stepReadings.reduce(0) { $0 + Int($1.count) }
        let avgSpO2 = SpO2Calibration.nightlyAverage(readings: spo2Readings) ?? 0

        let hrvBaseline = store.loadBaseline(metric: "hrv")
        let hrBaseline = store.loadBaseline(metric: "resting_hr")
        let readiness = ReadinessScoring.score(
            currentHRV: latestHRV > 0 ? latestHRV : (hrvBaseline?.mean ?? 0),
            baselineHRV: hrvBaseline?.mean ?? latestHRV,
            currentRestingHR: latestHeartRate > 0 ? latestHeartRate : (hrBaseline?.mean ?? 0),
            baselineRestingHR: hrBaseline?.mean ?? latestHeartRate,
            tempDeviation: 0,
            sleepScore: sleepScore,
            recoveryIndex: 0.7
        )

        let cal = ActivityScoring.estimateCalories(steps: UInt32(totalSteps))
        let activity = ActivityScoring.score(totalSteps: UInt32(totalSteps), activeCalories: cal)

        store.saveDailySummary(
            date: today,
            steps: totalSteps,
            avgHR: latestHeartRate,
            minHR: latestHeartRate,
            avgHRV: latestHRV,
            avgSpO2: avgSpO2,
            avgTemp: latestTemperature,
            sleepScore: sleepScore,
            readinessScore: readiness.total,
            activityScore: activity.total
        )
    }

    private func resetState() {
        responseTimer?.invalidate()
        responseTimer = nil
        responseIdleTimer?.invalidate()
        responseIdleTimer = nil
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
        responseCallback = nil
        connectedPeripheral = nil
        cmdCharacteristic = nil
        dataCharacteristic = nil
        gattReady = false
        isSyncing = false
        connectionState = .disconnected
        responseBuffer.removeAll()
        pairingMessage = ""
        syncStatus = ""
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            connectionState = .error("Bluetooth is \(central.state == .poweredOff ? "off" : "unavailable")")
        }
    }


    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let pid = peripheral.identifier
        guard discoveredPeripherals[pid] == nil else { return }

        discoveredPeripherals[pid] = peripheral
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown Ring"

        discoveredRings.append(DiscoveredRingInfo(id: pid, name: name, rssi: RSSI.intValue))
        log.info("Discovered: \(name) [\(pid)]")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("Connected to \(peripheral.name ?? "ring")")
        peripheral.discoverServices([OuraBLE.primaryServiceUUID, OuraBLE.auxServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error, isPeerRemovedError(error) {
            pairingMessage = "iOS has a stale Bluetooth bond for this ring.\n\nFix: Settings → Bluetooth → find the Oura ring → Forget This Device, then try again."
            connectionState = .error("Stale Bluetooth pairing — forget device in Settings")
        } else {
            connectionState = .error(error?.localizedDescription ?? "Connection failed")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error, isPeerRemovedError(error) {
            pairingMessage = "Bluetooth bond expired. Settings → Bluetooth → Forget the Oura ring, then reconnect."
            connectionState = .error("Stale Bluetooth pairing — forget device in Settings")
            connectedPeripheral = nil
            cmdCharacteristic = nil
            dataCharacteristic = nil
            gattReady = false
        } else {
            log.info("Disconnected from \(peripheral.name ?? "ring")")
            resetState()
        }
    }

    private func isPeerRemovedError(_ error: Error) -> Bool {
        let text = error.localizedDescription
        return text.contains("Code=14") || text.contains("Peer removed pairing")
            || text.contains("peer removed") || text.contains("encryption")
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }

        for char in chars {
            switch char.uuid {
            case OuraBLE.cmdCharUUID:
                cmdCharacteristic = char
            case OuraBLE.dataCharUUID:
                dataCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            case OuraBLE.extDataCharUUID, OuraBLE.notifyACharUUID, OuraBLE.notifyBCharUUID:
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }
            default:
                break
            }
        }

        // Only trigger once when both characteristics are found
        if !gattReady && cmdCharacteristic != nil && dataCharacteristic != nil {
            gattReady = true
            log.info("GATT ready, starting auth/pair flow")
            onGATTReady()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }

        let isDataChar = characteristic.uuid == OuraBLE.dataCharUUID
        let charName: String = switch characteristic.uuid {
        case OuraBLE.dataCharUUID: "data"
        case OuraBLE.extDataCharUUID: "ext"
        case OuraBLE.notifyACharUUID: "notifyA"
        case OuraBLE.notifyBCharUUID: "notifyB"
        case OuraBLE.cmdCharUUID: "cmd"
        default: "unknown"
        }
        log.info("RX [\(charName)] \(data.count)B: \(data.prefix(min(20, data.count)).map { String(format: "%02x", $0) }.joined(separator: " "))")

        if isDataChar {
            // Always check for live HR push notifications FIRST — even during command response collection.
            // Without this, pushed IBI frames get swallowed by the response buffer.
            if let packet = ParsedPacket.parse(data), let hr = packet.liveHR {
                log.info("Live HR: \(Int(hr.bpm)) BPM (IBI \(hr.ibiMs)ms)")
                latestHeartRate = hr.bpm
                let reading = IBIReading(timestamp: Date(), intervalMs: hr.ibiMs)
                ibiReadings.append(reading)
                if ibiReadings.count >= 10 {
                    latestHRV = HRVAnalysis.rmssd(from: ibiReadings.suffix(30).map { Double($0.intervalMs) })
                }
                return
            }

            // Log any subscription notification we didn't parse as liveHR (debug)
            if let packet = ParsedPacket.parse(data), packet.tag == 0x2F,
               packet.payload.count >= 2, packet.payload[0] == 0x28 {
                log.info("Subscription push (not parsed as HR): feature=\(packet.payload[1]) payload=\(packet.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
            }

            if responseCallback != nil {
                responseBuffer.append(data)
                onDataCharResponse()
            } else {
                let events = SensorEvent.parseEvents(from: data)
                if !events.isEmpty {
                    log.info("Live events from [data]: \(events.count) events")
                    processEvents(events)
                }
            }
            return
        }

        // Non-DATA notify chars: check for live HR push, then sensor events
        if let packet = ParsedPacket.parse(data), let hr = packet.liveHR {
            log.info("Live HR [\(charName)]: \(Int(hr.bpm)) BPM (IBI \(hr.ibiMs)ms)")
            latestHeartRate = hr.bpm
            ibiReadings.append(IBIReading(timestamp: Date(), intervalMs: hr.ibiMs))
            if ibiReadings.count >= 10 {
                latestHRV = HRVAnalysis.rmssd(from: ibiReadings.suffix(30).map { Double($0.intervalMs) })
            }
            return
        }
        let events = SensorEvent.parseEvents(from: data)
        if !events.isEmpty {
            log.info("Live events from [\(charName)]: \(events.count) events")
            processEvents(events)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log.error("Write failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Data hex helper

extension Data {
    init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
