import Foundation
import UserNotifications
import SwiftData

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

// MARK: - Contracts

extension NotificationService {
    func scheduleContractReminders(for contract: Contract) {
        cancelContractReminders(for: contract)
        let center = UNUserNotificationCenter.current()
        for reminder in contract.reminders(asOf: .now) {
            let content = UNMutableNotificationContent()
            let date = Formatting.date.string(from: reminder.eventDate)
            switch reminder.kind {
            case .cancellation:
                content.title = "Kündigungsfrist endet bald"
                content.body = "\(contract.provider): noch bis \(date) kündbar."
            case .priceGuarantee:
                content.title = "Preisgarantie endet"
                content.body = "\(contract.provider): Preisgarantie bis \(date)."
            }
            content.sound = .default
            if let meterID = contract.meter?.id { content.userInfo = ["meterID": meterID.uuidString] }

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = reminder.kind == .cancellation ? cancelIdentifier(for: contract) : guaranteeIdentifier(for: contract)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
        }
    }

    func cancelContractReminders(for contract: Contract) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [cancelIdentifier(for: contract), guaranteeIdentifier(for: contract)]
        )
    }

    /// Re-plans every contract, e.g. after an automatic renewal moved the deadline.
    func rescheduleAllContractReminders(_ context: ModelContext) {
        let contracts = (try? context.fetch(FetchDescriptor<Contract>())) ?? []
        contracts.forEach(scheduleContractReminders)
    }

    private func cancelIdentifier(for contract: Contract) -> String { "contract-cancel-\(contract.id.uuidString)" }
    private func guaranteeIdentifier(for contract: Contract) -> String { "contract-guarantee-\(contract.id.uuidString)" }
}
