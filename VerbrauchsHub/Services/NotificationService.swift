import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    func scheduleReminder(for meter: Meter) {
        let center = UNUserNotificationCenter.current()
        cancelReminder(for: meter)
        guard meter.reminderEnabled, let day = meter.reminderDayOfMonth else { return }

        let content = UNMutableNotificationContent()
        content.title = "Zählerstand ablesen"
        content.body = "\(meter.displayName) — vergiss nicht, den aktuellen Stand einzutragen."
        content.sound = .default
        content.userInfo = ["meterID": meter.id.uuidString]

        var components = DateComponents()
        components.day = day
        components.hour = 19
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: identifier(for: meter), content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    func cancelReminder(for meter: Meter) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: meter)])
    }

    private func identifier(for meter: Meter) -> String {
        "meter-reminder-\(meter.id.uuidString)"
    }
}
