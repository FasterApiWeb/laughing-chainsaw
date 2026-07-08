import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var showExport = false
    @State private var exportData: Data?
    @State private var exportFilename = ""
    @State private var exportStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var exportEndDate = Date()

    var body: some View {
        NavigationStack {
            List {
                Section("Apple Health") {
                    HStack {
                        Label("HealthKit", systemImage: "heart.fill")
                        Spacer()
                        Text(healthKit.isAuthorized ? "Connected" : "Not Authorized")
                            .foregroundStyle(healthKit.isAuthorized ? .green : .red)
                    }

                    if !healthKit.isAuthorized {
                        Button("Authorize Health Access") {
                            Task { await healthKit.requestAuthorization() }
                        }
                    }

                    Text("LibreRing writes heart rate, HRV, SpO2, temperature, sleep stages, and steps to Apple Health automatically after each sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data Export") {
                    DatePicker("From", selection: $exportStartDate, displayedComponents: .date)
                    DatePicker("To", selection: $exportEndDate, displayedComponents: .date)

                    Button {
                        exportData = LocalStore.shared.exportJSON(
                            from: exportStartDate,
                            to: exportEndDate
                        )
                        if exportData != nil {
                            exportFilename = "librering-export-\(dateStamp()).json"
                            showExport = true
                        }
                    } label: {
                        Label("Export as JSON", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportData = LocalStore.shared.exportCSV(
                            from: exportStartDate,
                            to: exportEndDate
                        )
                        if exportData != nil {
                            exportFilename = "librering-export-\(dateStamp()).csv"
                            showExport = true
                        }
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                }

                Section("Cloud Sync") {
                    SyncSettingsSection()
                }

                Section("Privacy") {
                    Label("End-to-End Local First", systemImage: "lock.shield")
                    Label("Optional Cloud Backup", systemImage: "icloud")
                    Label("No Analytics or Tracking", systemImage: "eye.slash")

                    Text("LibreRing stores data on-device by default. Enable cloud sync in Settings to back up to your Supabase account. Large exports use Cloudflare R2.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    InfoRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    InfoRow(label: "License", value: "MIT")

                    Link(destination: URL(string: "https://github.com/FasterApiWeb/laughing-chainsaw")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }

                    Text("LibreRing is open-source software. You own your hardware and your data. This app uses clean-room reverse engineering under DMCA §1201(f) for interoperability.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showExport) {
                if let data = exportData {
                    ShareSheet(data: data, filename: exportFilename)
                }
            }
        }
    }

    private func dateStamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let data: Data
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
