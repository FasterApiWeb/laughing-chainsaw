import SwiftUI

@main
struct LibreRingApp: App {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var healthKit = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(healthKit)
                .task {
                    await healthKit.requestAuthorization()
                }
        }
    }
}
