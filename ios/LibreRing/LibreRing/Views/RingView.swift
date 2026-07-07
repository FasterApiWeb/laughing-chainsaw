import SwiftUI

struct RingView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var showFactoryReset = false

    var body: some View {
        NavigationStack {
            List {
                if ble.connectionState == .connected {
                    Section("Device") {
                        InfoRow(label: "Name", value: ble.ringInfo.name)
                        InfoRow(label: "Firmware", value: ble.ringInfo.firmwareVersion)
                        InfoRow(label: "API Version", value: ble.ringInfo.apiVersion)
                        InfoRow(label: "BLE MAC", value: ble.ringInfo.bleMac)
                        InfoRow(label: "Battery", value: "\(ble.ringInfo.batteryPercent)%\(ble.ringInfo.isCharging ? " ⚡" : "")")
                    }

                    Section("Sync") {
                        Button {
                            ble.triggerSync()
                        } label: {
                            HStack {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if ble.isSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(ble.isSyncing)
                        .onChange(of: ble.isSyncing) { wasSyncing, nowSyncing in
                            if wasSyncing && !nowSyncing {
                                Task { await healthKit.writeAll(from: ble) }
                            }
                        }

                        if !ble.syncStatus.isEmpty {
                            HStack {
                                if ble.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 4)
                                }
                                Text(ble.syncStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let lastSync = ble.lastSyncDate {
                            InfoRow(label: "Last Sync", value: lastSync.formatted(.relative(presentation: .named)))
                        }
                    }

                    Section("Data Collected") {
                        InfoRow(label: "Heart Rate", value: "\(ble.ibiReadings.count) readings")
                        InfoRow(label: "SpO2", value: "\(ble.spo2Readings.count) readings")
                        InfoRow(label: "Temperature", value: "\(ble.temperatureReadings.count) readings")
                        InfoRow(label: "Sleep Phases", value: "\(ble.sleepPhases.count) entries")
                        InfoRow(label: "Steps", value: "\(ble.stepReadings.count) entries")
                    }

                    if !healthKit.sampleCounts.isEmpty {
                        Section("Apple Health") {
                            ForEach(healthKit.sampleCounts.sorted(by: { $0.key < $1.key }), id: \.key) { key, count in
                                InfoRow(label: key.capitalized, value: "\(count) samples written")
                            }
                        }
                    }

                    if ble.ibiReadings.isEmpty && ble.ringInfo.batteryPercent == 0 {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Not receiving data?", systemImage: "exclamationmark.triangle")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Text("1. Force-quit the Oura app (swipe up in app switcher)\n2. Tap Sync Now above\n3. If still no data, tap Disconnect, then reconnect\n4. If the ring was paired via the Oura app, you may need to Factory Reset it below and re-pair with LibreRing only")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section {
                        Button("Disconnect") {
                            ble.disconnect()
                        }

                        Button("Factory Reset Ring", role: .destructive) {
                            showFactoryReset = true
                        }
                    } footer: {
                        Text("Erases pairing key and stored data. Ring must be re-paired after reset.")
                    }
                } else {
                    Section {
                        NavigationLink {
                            ScannerView()
                        } label: {
                            Label("Connect Ring", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No Subscription Required")
                                .font(.headline)
                            Text("LibreRing connects directly to your Oura Ring hardware over Bluetooth. Your data stays on your device and syncs to Apple Health. No cloud. No subscription. No $6/month.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Ring")
            .alert("Factory Reset", isPresented: $showFactoryReset) {
                Button("Reset", role: .destructive) {
                    ble.factoryReset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This erases the ring's pairing key and all stored data. You'll need to re-pair after reset. Place the ring on its charger after resetting.")
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}
