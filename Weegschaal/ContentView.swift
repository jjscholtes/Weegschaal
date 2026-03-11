import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var geselecteerdTab = 0

    var body: some View {
        TabView(selection: $geselecteerdTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "scalemass.fill")
                }
                .tag(0)

            GeschiedenisView()
                .tabItem {
                    Label("Geschiedenis", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(1)

            InstellingenView()
                .tabItem {
                    Label("Instellingen", systemImage: "person.fill")
                }
                .tag(2)
        }
    }
}
