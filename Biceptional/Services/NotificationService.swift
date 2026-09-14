import Foundation
import UserNotifications

/// Local reminders only — no server, no push certificate.
/// Morning recovery, consistent weight-log time, evening food log.
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func reschedule(preferences: UserPreferences) async {
        center.removeAllPendingNotificationRequests()
        guard preferences.notificationsEnabled else { return }
        await requestAuthorizationIfNeeded()

        schedule(
            id: "recovery.morning",
            title: String(localized: "Recovery is ready"),
            body: String(localized: "Last night’s scores are in. Open Biceptional to see Recovery and Sleep."),
            hour: preferences.morningRecoveryHour
        )
        schedule(
            id: "weight.daily",
            title: String(localized: "Log weight"),
            body: String(localized: "Same time every day keeps the 7-day average honest."),
            hour: preferences.weightReminderHour
        )
        schedule(
            id: "food.evening",
            title: String(localized: "Log food"),
            body: String(localized: "Capture dinner while you still remember the ghee."),
            hour: preferences.foodReminderHour
        )
    }

    private func schedule(id: String, title: String, body: String, hour: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }
}
