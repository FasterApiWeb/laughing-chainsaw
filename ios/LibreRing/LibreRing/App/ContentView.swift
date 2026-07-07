import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "heart.text.square")
                }

            RingView()
                .tabItem {
                    Label("Ring", systemImage: "circle.circle")
                }

            SleepView()
                .tabItem {
                    Label("Sleep", systemImage: "bed.double")
                }

            TrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.purple)
    }
}
