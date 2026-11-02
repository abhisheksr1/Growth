import Foundation
import SwiftData
import UserNotifications

@MainActor
enum NotificationScheduler {
    static func reschedule(context: ModelContext) async {
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        let snapshots = reminders.compactMap(\.schedulingSnapshot)
        await apply(snapshots)
    }

    static func apply(_ snapshots: [ReminderSnapshot]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let settings = await notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        else {
            return
        }
        for snapshot in snapshots where snapshot.shouldSchedule {
            guard let request = makeRequest(snapshot) else { continue }
            try? await center.add(request)
        }
    }

    static func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func makeRequest(_ snapshot: ReminderSnapshot) -> UNNotificationRequest? {
        let content = UNMutableNotificationContent()
        content.title = snapshot.title
        content.body = snapshot.body
        content.sound = .default
        if let goalID = snapshot.goalID {
            content.threadIdentifier = goalID.uuidString
            content.userInfo = ["reminderID": snapshot.id.uuidString, "goalID": goalID.uuidString]
        } else {
            content.threadIdentifier = "check-in"
            content.userInfo = ["reminderID": snapshot.id.uuidString]
        }

        let trigger: UNCalendarNotificationTrigger
        switch snapshot.recurrence {
        case .none:
            guard let next = ReminderScheduling.nextFireDate(snapshot) else { return nil }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        case .daily:
            trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: snapshot.hour, minute: snapshot.minute),
                repeats: true
            )
        case .weekly:
            trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: snapshot.hour, minute: snapshot.minute, weekday: snapshot.weekday),
                repeats: true
            )
        case .monthly:
            let day = Calendar.current.component(.day, from: snapshot.fireOn)
            trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(day: day, hour: snapshot.hour, minute: snapshot.minute),
                repeats: true
            )
        }
        return UNNotificationRequest(identifier: snapshot.id.uuidString, content: content, trigger: trigger)
    }
}

@MainActor
@Observable
final class NotificationPermission {
    var status: UNAuthorizationStatus = .notDetermined

    var isDenied: Bool { status == .denied }

    var canSchedule: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    func refresh() async {
        status = await NotificationScheduler.notificationSettings().authorizationStatus
    }

    func request() async -> Bool {
        let granted = await NotificationScheduler.requestAuthorization()
        await refresh()
        return granted
    }
}
