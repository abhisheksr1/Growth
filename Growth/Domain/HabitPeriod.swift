import Foundation

struct HabitSchedule: Equatable, Sendable {
    var frequency: HabitFrequency
    var weekdayMask: Int
    var weeklyQuota: Int
}

struct HabitPeriodSnapshot: Equatable, Sendable {
    var completed: Int
    var expected: Int
    var fraction: Double
    var start: Date
    var end: Date
}

struct HabitDayMark: Equatable, Identifiable, Sendable {
    enum State: Equatable, Sendable {
        case logged
        case open
        case later
        case off
    }

    var date: Date
    var state: State
    var id: Date { date }
}

enum HabitLogError: LocalizedError, Equatable, Sendable {
    case future
    case alreadyLogged
    case notScheduledThatDay
    case quotaFilled

    var errorDescription: String? {
        switch self {
        case .future:
            "A habit can be logged today or on a past day."
        case .alreadyLogged:
            "There's already a log for that day."
        case .notScheduledThatDay:
            "This habit isn't scheduled on that day."
        case .quotaFilled:
            "You've already logged as many times as this week's quota."
        }
    }
}

enum HabitPeriod {
    static func current(
        schedule: HabitSchedule,
        logDates: [Date],
        now: Date,
        calendar: Calendar
    ) -> HabitPeriodSnapshot {
        snapshot(weekOffset: 0, schedule: schedule, logDates: logDates, now: now, calendar: calendar)
    }

    static func previous(
        schedule: HabitSchedule,
        logDates: [Date],
        now: Date,
        calendar: Calendar,
        count: Int = 3
    ) -> [HabitPeriodSnapshot] {
        guard count > 0 else { return [] }
        return (1...count).map {
            snapshot(weekOffset: -$0, schedule: schedule, logDates: logDates, now: now, calendar: calendar)
        }
    }

    static func weekMarks(
        schedule: HabitSchedule,
        logDates: [Date],
        now: Date,
        calendar: Calendar
    ) -> [HabitDayMark] {
        let weekStart = startOfWeek(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let logDays = Set(logDates.map { calendar.startOfDay(for: $0) })
        return (0..<7).compactMap { offset -> HabitDayMark? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let day = calendar.startOfDay(for: date)
            let scheduled = isScheduled(schedule, on: day, calendar: calendar) || schedule.frequency == .weeklyQuota
            let state: HabitDayMark.State
            if schedule.frequency == .weekdays && !isScheduled(schedule, on: day, calendar: calendar) {
                state = .off
            } else if logDays.contains(day) {
                state = .logged
            } else if day > today {
                state = .later
            } else if scheduled {
                state = .open
            } else {
                state = .off
            }
            return HabitDayMark(date: day, state: state)
        }
    }

    static func validationError(
        schedule: HabitSchedule,
        existingLogDays: [Date],
        day: Date,
        now: Date,
        calendar: Calendar
    ) -> HabitLogError? {
        let target = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        if target > today {
            return .future
        }
        let existing = Set(existingLogDays.map { calendar.startOfDay(for: $0) })
        if existing.contains(target) {
            return .alreadyLogged
        }
        switch schedule.frequency {
        case .daily:
            return nil
        case .weekdays:
            return isScheduled(schedule, on: target, calendar: calendar) ? nil : .notScheduledThatDay
        case .weeklyQuota:
            let interval = weekInterval(containing: target, calendar: calendar)
            let count = existing.filter { $0 >= interval.start && $0 < interval.end }.count
            let quota = max(schedule.weeklyQuota, 0)
            return count >= quota ? .quotaFilled : nil
        }
    }

    static func isScheduled(_ schedule: HabitSchedule, on day: Date, calendar: Calendar) -> Bool {
        switch schedule.frequency {
        case .daily, .weeklyQuota:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: day)
            return WeekdayMask.contains(schedule.weekdayMask, weekday: weekday)
        }
    }

    private static func snapshot(
        weekOffset: Int,
        schedule: HabitSchedule,
        logDates: [Date],
        now: Date,
        calendar: Calendar
    ) -> HabitPeriodSnapshot {
        let thisWeek = startOfWeek(containing: now, calendar: calendar)
        let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeek) ?? thisWeek
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let logDays = Set(logDates.map { calendar.startOfDay(for: $0) })

        if schedule.frequency == .weeklyQuota {
            let completed = logDays.filter { $0 >= weekStart && $0 < weekEnd }.count
            let expected = max(schedule.weeklyQuota, 0)
            return HabitPeriodSnapshot(
                completed: completed,
                expected: expected,
                fraction: ProgressMath.ratio(completed: completed, expected: expected),
                start: weekStart,
                end: weekOffset == 0 ? calendar.startOfDay(for: now) : calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            )
        }

        let lastDay = weekOffset == 0
            ? calendar.startOfDay(for: now)
            : (calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart)
        var expected = 0
        var completed = 0
        var day = weekStart
        while day <= lastDay {
            if isScheduled(schedule, on: day, calendar: calendar) {
                expected += 1
                if logDays.contains(calendar.startOfDay(for: day)) {
                    completed += 1
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return HabitPeriodSnapshot(
            completed: completed,
            expected: expected,
            fraction: ProgressMath.ratio(completed: completed, expected: expected),
            start: weekStart,
            end: lastDay
        )
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        let start = startOfWeek(containing: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}
