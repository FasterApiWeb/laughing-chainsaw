import SwiftUI

struct ScannerView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) private var dismiss
    @State private var showKeyImport = false
    @State private var keyHex = ""
    @State private var showFactoryResetConfirm = false

    var body: some View {
        List {
            Section {
                if ble.discoveredRings.isEmpty && ble.connectionState == .scanning {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Searching for Oura rings...")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(ble.discoveredRings) { ring in
                    Button {
                        ble.connect(ringID: ring.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ring.name)
                                    .font(.headline)
                                Text("Signal: \(ring.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    .disabled(isConnecting)
                }
            } header: {
                Text("Nearby Rings")
            }

            if isConnecting {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        VStack(alignment: .leading) {
                            Text(progressLabel)
                                .font(.subheadline)
                            if !ble.pairingMessage.isEmpty {
                                Text(ble.pairingMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if case .error = ble.connectionState {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if !ble.pairingMessage.isEmpty {
                            Text(ble.pairingMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Connection failed", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }

                        HStack(spacing: 12) {
                            Button("Retry Scan") {
                                ble.startScanning()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)

                            Button("Import Key") {
                                showKeyImport = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if ble.connectionState == .connected {
                Section {
                    Label("Connected to \(ble.ringInfo.name)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    if ble.ringInfo.batteryPercent > 0 {
                        HStack {
                            Text("Battery")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(ble.ringInfo.batteryPercent)%\(ble.ringInfo.isCharging ? " charging" : "")")
                        }
                    }

                    if !ble.ringInfo.firmwareVersion.isEmpty {
                        HStack {
                            Text("Firmware")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(ble.ringInfo.firmwareVersion)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    Button("Go to Dashboard") {
                        dismiss()
                    }
                    .font(.headline)
                }

                Section {
                    Button(role: .destructive) {
                        showFactoryResetConfirm = true
                    } label: {
                        Label("Factory Reset Ring", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Erases the ring's auth key and all stored data. You'll need to re-pair after reset.")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("How to Connect", systemImage: "info.circle")
                        .font(.headline)

                    StepRow(number: 1, text: "Factory reset your ring — open the Oura app → Settings → Reset, OR use the Factory Reset button above if connected")
                    StepRow(number: 2, text: "Place ring on charger near your iPhone and wait 30 seconds")
                    StepRow(number: 3, text: "Tap your ring above — LibreRing will auto-pair and start reading data")
                    StepRow(number: 4, text: "If you see a 'Stale Bluetooth pairing' error, go to Settings → Bluetooth → Forget the Oura ring, then retry")
                }
            } header: {
                Text("Setup")
            } footer: {
                Text("After pairing with LibreRing, your ring will no longer sync with the Oura app. Your data stays on this device and syncs to Apple Health. No subscription needed.")
            }
        }
        .navigationTitle("Connect Ring")
        .onAppear { ble.startScanning() }
        .onDisappear {
            if ble.connectionState == .scanning {
                ble.stopScanning()
            }
        }
        .sheet(isPresented: $showKeyImport) {
            KeyImportSheet(keyHex: $keyHex) {
                if ble.importKey(keyHex) {
                    showKeyImport = false
                    if let ring = ble.discoveredRings.first {
                        ble.connect(ringID: ring.id)
                    }
                }
            }
        }
        .alert("Factory Reset", isPresented: $showFactoryResetConfirm) {
            Button("Reset", role: .destructive) {
                ble.factoryReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will erase the ring's pairing key and all stored sensor data. The ring will need to be re-paired.")
        }
    }

    private var isConnecting: Bool {
        [.connecting, .authenticating, .pairing].contains(ble.connectionState)
    }

    private var progressLabel: String {
        switch ble.connectionState {
        case .connecting: "Connecting..."
        case .authenticating: "Authenticating..."
        case .pairing: "Pairing with ring..."
        default: ""
        }
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(.purple.opacity(0.15))
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}

struct KeyImportSheet: View {
    @Binding var keyHex: String
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("32-character hex key", text: $keyHex)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Auth Key")
                } footer: {
                    Text("If you previously paired with the Python tools, paste the contents of key.hex here (32 hex characters = 16 bytes).")
                }

                Button("Import Key") {
                    onImport()
                }
                .disabled(keyHex.trimmingCharacters(in: .whitespacesAndNewlines).count != 32)
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
