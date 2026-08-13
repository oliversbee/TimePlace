import Foundation
import UserNotifications

/// Schedules a local notification at a random time between 9am and 9pm
/// each day, prompting the user to take their photo.
///
/// Note: real BeReal fires everyone's notification at the same
/// server-chosen moment via a push notification, which needs a backend
/// (e.g. a scheduled Supabase Edge Function + APNs). This local-notification
/// version picks its own random time per device, which is the practical
/// equivalent for a self-contained client app.
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    private let daysToSchedule = 7
    private let earliestHour = 9   // 9am
    private let latestHour = 21    // 9pm

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                self.scheduleUpcomingPrompts()
            }
        }
    }

    /// Fills in any missing days (up to `daysToSchedule` ahead) with a
    /// freshly-randomized notification time. Safe to call repeatedly —
    /// it won't duplicate a day that's already scheduled.
    func scheduleUpcomingPrompts() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let alreadyScheduled = Set(requests.map { $0.identifier })
            let calendar = Calendar.current

            for offset in 0..<self.daysToSchedule {
                guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
                let identifier = "daily-photo-\(self.dateKey(for: day))"
                if alreadyScheduled.contains(identifier) { continue }
                guard let fireDate = self.randomTime(on: day), fireDate > Date() else { continue }
                self.schedule(identifier: identifier, date: fireDate)
            }
        }
    }

    private func randomTime(on day: Date) -> Date? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        guard
            let earliest = calendar.date(bySettingHour: earliestHour, minute: 0, second: 0, of: startOfDay),
            let latest = calendar.date(bySettingHour: latestHour, minute: 0, second: 0, of: startOfDay)
        else { return nil }

        let interval = latest.timeIntervalSince(earliest)
        let randomOffset = TimeInterval.random(in: 0...interval)
        return earliest.addingTimeInterval(randomOffset)
    }

    private func schedule(identifier: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Time+Place"
        content.body = "Open the app and capture your moment."
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
