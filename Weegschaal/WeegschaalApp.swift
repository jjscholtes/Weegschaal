import SwiftUI
import SwiftData

@main
struct WeegschaalApp: App {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var reminders = ReminderManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
                .environmentObject(healthKit)
                .environmentObject(reminders)
        }
        .modelContainer(for: Meting.self)
    }
}
