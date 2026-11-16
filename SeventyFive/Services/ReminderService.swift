import Foundation
import UserNotifications

/// Local daily check-in reminders. Nothing goes through a server.
///
/// Rather than one repeating notification, this schedules the next seven days individually
/// and is re-run whenever the app opens or the day's checklist changes. That lets it stay
/// quiet on a day that's already done — a repeating trigger can't skip a single day — and
/// tailor the message to the tier.
enum ReminderService {
    private static let idPrefix = "75.reminder."
    private static let horizonDays = 7

    static func requestPermission() async -> Bool {
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

    /// Replaces any pending reminders with a fresh week.
    ///
    /// - Parameters:
    ///   - minutesAfterMidnight: local time to fire each day.
    ///   - todayComplete: skip today's reminder when the checklist is already done.
    ///   - mode: shapes the wording; 75 Hard's message mentions the reset rule.
    ///   - currentDay / totalDays: number the messages, and schedule nothing past the
    ///     final day of the challenge.
    static func reschedule(minutesAfterMidnight: Int, todayComplete: Bool, mode: ChallengeMode, currentDay: Int, totalDays: Int) {
        let center = UNUserNotificationCenter.current()
        cancelAll()

        let calendar = Calendar.current
        let now = Date()
        let lastDayOffset = max(0, totalDays - currentDay)

        for offset in 0..<min(horizonDays, lastDayOffset + 1) {
            if offset == 0 && todayComplete { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fireDate = calendar.date(byAdding: .minute, value: minutesAfterMidnight, to: day),
                  fireDate > now
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Day \(currentDay + offset) check-in"
            content.body = message(for: mode)
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: idPrefix + "\(offset)", content: content, trigger: trigger))
        }
    }

    static func cancelAll() {
        let ids = (0..<horizonDays).map { idPrefix + "\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func message(for mode: ChallengeMode) -> String {
        switch mode {
        case .soft: return "Your checklist is still open. A few minutes now keeps the habit going."
        case .medium: return "Your checklist is still open — every finished day protects your misses budget."
        case .hard: return "Your checklist is still open. 75 Hard restarts on a missed task."
        }
    }
}
