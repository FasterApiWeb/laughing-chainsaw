import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var healthKit: HealthKitManager

    private var breathingRate: Double? {
        BreathingRate.estimate(from: ble.ibiReadings.map { Double($0.intervalMs) })
    }

    private var activityScore: ActivityResult? {
        let totalSteps = UInt32(ble.stepReadings.reduce(0) { $0 + Int($1.count) })
        guard totalSteps > 0 else { return nil }
        let cal = ActivityScoring.estimateCalories(steps: totalSteps)
        return ActivityScoring.score(totalSteps: totalSteps, activeCalories: cal)
    }

    private var readinessScore: ReadinessResult? {
        let hrBaseline = LocalStore.shared.loadBaseline(metric: "resting_hr")
        let hrvBaseline = LocalStore.shared.loadBaseline(metric: "hrv")
        guard let sleepScore = SleepScoring.analyze(phases: ble.sleepPhases),
              ble.latestHRV > 0 else { return nil }

        return ReadinessScoring.score(
            currentHRV: ble.latestHRV,
            baselineHRV: hrvBaseline?.mean ?? ble.latestHRV,
            currentRestingHR: ble.latestHeartRate,
            baselineRestingHR: hrBaseline?.mean ?? ble.latestHeartRate,
            tempDeviation: 0,
            sleepScore: sleepScore.total,
            recoveryIndex: 0.7
        )
    }

    private var hasData: Bool {
        ble.latestHeartRate > 0 || ble.latestSpO2 > 0 || !ble.sleepPhases.isEmpty || ble.latestSteps > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if ble.connectionState != .connected {
                    ConnectionBanner()
                        .padding(.horizontal)
                }

                if !hasData && ble.connectionState == .connected {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Listening for sensor data...")
                            .font(.headline)
                        Text("Wear the ring on your finger. Heart rate data usually appears within 1-2 minutes. Temperature and SpO2 take longer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else if !hasData && ble.connectionState != .connected {
                    ContentUnavailableView(
                        "No Data Yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Connect your Oura Ring and sync to see your health metrics here.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 16) {
                        MetricCard(
                            title: "Heart Rate",
                            value: ble.latestHeartRate > 0 ? "\(Int(ble.latestHeartRate))" : "--",
                            unit: "BPM",
                            icon: "heart.fill",
                            color: .red
                        )

                        MetricCard(
                            title: "HRV",
                            value: ble.latestHRV > 0 ? "\(Int(ble.latestHRV))" : "--",
                            unit: "ms",
                            icon: "waveform.path.ecg",
                            color: .blue
                        )

                        MetricCard(
                            title: "SpO2",
                            value: ble.latestSpO2 > 0 ? "\(ble.latestSpO2)" : "--",
                            unit: "%",
                            icon: "lungs.fill",
                            color: .cyan
                        )

                        MetricCard(
                            title: "Temperature",
                            value: ble.latestTemperature > 0 ? String(format: "%.1f", ble.latestTemperature) : "--",
                            unit: "°C",
                            icon: "thermometer.medium",
                            color: .orange
                        )

                        MetricCard(
                            title: "Steps",
                            value: ble.latestSteps > 0 ? "\(ble.latestSteps)" : "--",
                            unit: "steps",
                            icon: "figure.walk",
                            color: .green
                        )

                        MetricCard(
                            title: "Battery",
                            value: ble.ringInfo.batteryPercent > 0 ? "\(ble.ringInfo.batteryPercent)" : "--",
                            unit: "%",
                            icon: ble.ringInfo.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                            color: .mint
                        )

                        if let br = breathingRate {
                            MetricCard(
                                title: "Breathing",
                                value: String(format: "%.1f", br),
                                unit: "br/min",
                                icon: "wind",
                                color: .teal
                            )
                        }

                        if let spo2Avg = SpO2Calibration.nightlyAverage(readings: ble.spo2Readings) {
                            MetricCard(
                                title: "Avg SpO2",
                                value: String(format: "%.1f", spo2Avg),
                                unit: "%",
                                icon: "lungs",
                                color: .cyan.opacity(0.7)
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Score cards
                    VStack(spacing: 12) {
                        if let sleepScore = SleepScoring.analyze(phases: ble.sleepPhases) {
                            ScoreCard(
                                title: "Sleep Score",
                                score: sleepScore.total,
                                label: sleepScore.label,
                                color: .indigo
                            )
                        }

                        if let readiness = readinessScore {
                            ScoreCard(
                                title: "Readiness",
                                score: readiness.total,
                                label: readiness.label,
                                color: .orange
                            )
                        }

                        if let activity = activityScore {
                            ScoreCard(
                                title: "Activity",
                                score: activity.total,
                                label: activity.label,
                                color: .green
                            )
                        }
                    }
                    .padding(.horizontal)

                    if let lastSync = ble.lastSyncDate {
                        Text("Last sync: \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    if let lastWrite = healthKit.lastWriteDate {
                        Label(
                            "Synced to Apple Health \(lastWrite.formatted(.relative(presentation: .named)))",
                            systemImage: "heart.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("LibreRing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        ble.triggerSync()
                    } label: {
                        if ble.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(ble.connectionState != .connected || ble.isSyncing)
                }
            }
            .onChange(of: ble.isSyncing) { wasSyncing, nowSyncing in
                if wasSyncing && !nowSyncing {
                    Task { await healthKit.writeAll(from: ble) }
                }
            }
        }
    }
}

// MARK: - Components

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
                Spacer()
            }

            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ScoreCard: View {
    let title: String
    let score: Int
    let label: String
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
            }
            .frame(width: 64, height: 64)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ConnectionBanner: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(statusText)
                .font(.subheadline)
            Spacer()
            if ble.connectionState == .disconnected {
                NavigationLink("Connect") {
                    ScannerView()
                }
                .font(.subheadline.bold())
            }
        }
        .padding()
        .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusIcon: String {
        switch ble.connectionState {
        case .disconnected: "circle.slash"
        case .scanning: "antenna.radiowaves.left.and.right"
        case .connecting, .authenticating, .pairing: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch ble.connectionState {
        case .disconnected: .secondary
        case .scanning, .connecting, .authenticating, .pairing: .blue
        case .connected: .green
        case .error: .red
        }
    }

    private var statusText: String {
        switch ble.connectionState {
        case .disconnected: "Ring not connected"
        case .scanning: "Scanning..."
        case .connecting: "Connecting..."
        case .authenticating: "Authenticating..."
        case .pairing: "Pairing..."
        case .connected: "Connected"
        case .error(let msg): msg
        }
    }
}
