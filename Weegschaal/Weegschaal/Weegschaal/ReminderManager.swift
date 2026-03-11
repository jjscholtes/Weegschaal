import Foundation
import Combine
import UserNotifications

enum ReminderStatus: Equatable {
    case nietBepaald
    case geweigerd
    case geautoriseerd
    case voorlopig
    case onbekend

    var label: String {
        switch self {
        case .nietBepaald: return "Nog niet gevraagd"
        case .geweigerd: return "Geweigerd"
        case .geautoriseerd: return "Geautoriseerd"
        case .voorlopig: return "Voorlopig"
        case .onbekend: return "Onbekend"
        }
    }
}

final class ReminderManager: ObservableObject {
    private let center = UNUserNotificationCenter.current()
    private let reminderId = "dagelijkse-meting-herinnering"

    @Published private(set) var status: ReminderStatus = .nietBepaald

    init() {
        verversStatus()
    }

    func verversStatus() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = self.mapStatus(settings.authorizationStatus)
            }
        }
    }

    func vraagToestemming(completion: @escaping (Bool, String?) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.verversStatus()
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                if granted {
                    completion(true, nil)
                } else {
                    completion(false, "Notificaties zijn uitgeschakeld voor deze app.")
                }
            }
        }
    }

    func planDagelijkseHerinnering(uur: Int, minuut: Int, completion: @escaping (Bool, String?) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "Tijd om te meten"
        content.body = "Doe een nieuwe weging om je trend actueel te houden."
        content.sound = .default

        var components = DateComponents()
        components.hour = uur
        components.minute = minuut

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderId, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [reminderId])
        center.add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    completion(true, nil)
                }
            }
        }
    }

    func verwijderHerinneringen() {
        center.removePendingNotificationRequests(withIdentifiers: [reminderId])
    }

    private func mapStatus(_ status: UNAuthorizationStatus) -> ReminderStatus {
        switch status {
        case .notDetermined: return .nietBepaald
        case .denied: return .geweigerd
        case .authorized: return .geautoriseerd
        case .provisional, .ephemeral: return .voorlopig
        @unknown default: return .onbekend
        }
    }
}
