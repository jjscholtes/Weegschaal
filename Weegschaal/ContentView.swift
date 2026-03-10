import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var geselecteerdTab: AppTab = .wegen

    var body: some View {
        TabView(selection: $geselecteerdTab) {
            LazyTabContent(isActive: geselecteerdTab == .wegen) {
                DashboardView()
            }
                .tabItem {
                    Label("Wegen", systemImage: "scalemass.fill")
                }
                .tag(AppTab.wegen)

            LazyTabContent(isActive: geselecteerdTab == .geschiedenis) {
                GeschiedenisView()
            }
                .tabItem {
                    Label("Geschiedenis", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.geschiedenis)

            LazyTabContent(isActive: geselecteerdTab == .instellingen) {
                InstellingenView()
            }
                .tabItem {
                    Label("Instellingen", systemImage: "person.fill")
                }
                .tag(AppTab.instellingen)
        }
    }
}

private enum AppTab: Hashable {
    case wegen
    case geschiedenis
    case instellingen
}

private struct LazyTabContent<Content: View>: View {
    let isActive: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if isActive {
                content()
            } else {
                Color.clear
            }
        }
    }
}
