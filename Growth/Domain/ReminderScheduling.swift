import Foundation

struct ReminderSnapshot: Equatable, Sendable {
    var id: UUID
    var kind: ReminderKind
    var goalID: UUID?
    var title: String
    var body: String
    var fireOn: Date
    var hour: Int
    var minute: Int
    var weekday: Int
    var recurrence: ReminderRecurrence
    var enabled: Bool
    var silenced: Bool

    var shouldSchedule: Bool {
        enabled && !silenced
    }
}

enum ReminderScheduling {
    /// The next local fire date. A one-shot time that has already passed returns nil.
    /// Repeating reminders roll forward in the supplied calendar.
    static func nextFireDate(
        fireOn: Date,
        hour: Int,
        minute: Int,
        weekday: Int,
        recurrence: ReminderRecurrence,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let hour = min(max(hour, 0), 23)
        let minute = min(max(minute, 0), 59)
        switch recurrence {
        case .none:
            let candidate = date(on: fireOn, hour: hour, minute: minute, calendar: calendar)
            return candidate > now ? candidate : nil
        case .daily:
            let today = date(on: now, hour: hour, minute: minute, calendar: calendar)
            if today > now { return today }
            return calendar.date(byAdding: .day, value: 1, to: today)
        case .weekly:
            let safeWeekday = (1...7).contains(weekday) ? weekday : calendar.component(.weekday, from: fireOn)
            let todayAtTime = date(on: now, hour: hour, minute: minute, calendar: calendar)
            let todayWeekday = calendar.component(.weekday, from: now)
            var delta = safeWeekday - todayWeekday
            if delta < 0 { delta += 7 }
            guard let candidate = calendar.date(byAdding: .day, value: delta, to: todayAtTime) else { return nil }
            if candidate > now { return candidate }
            return calendar.date(byAdding: .day, value: 7, to: candidate)
        case .monthly:
            let preferredDay = calendar.component(.day, from: fireOn)
            let thisMonth = clampedDay(preferredDay, in: now, hour: hour, minute: minute, calendar: calendar)
            if thisMonth > now { return thisMonth }
            let nextMonthAnchor = calendar.date(byAdding: .month, value: 1, to: now) ?? now
            return clampedDay(preferredDay, in: nextMonthAnchor, hour: hour, minute: minute, calendar: calendar)
        }
    }

    static func nextFireDate(_ snapshot: ReminderSnapshot, now: Date = .now, calendar: Calendar = .current) -> Date? {
        nextFireDate(
            fireOn: snapshot.fireOn,
            hour: snapshot.hour,
            minute: snapshot.minute,
            weekday: snapshot.weekday,
            recurrence: snapshot.recurrence,
            now: now,
            calendar: calendar
        )
    }

    private static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts) ?? day
    }

    private static func clampedDay(_ day: Int, in monthAnchor: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let range = calendar.range(of: .day, in: .month, for: monthAnchor) ?? 1..<29
        var parts = calendar.dateComponents([.year, .month], from: monthAnchor)
        parts.day = min(max(day, 1), range.count)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts) ?? monthAnchor
    }
}
