import XCTest
@testable import Growth

final class ProgressMathTests: XCTestCase {
    func testIncreaseProgress() {
        let value = ProgressMath.numericFraction(direction: .increase, start: 0, current: 25, target: 100)
        XCTAssertEqual(value ?? -1, 0.25, accuracy: 0.0001)
    }

    func testIncreaseClampsBelowStartAndAboveTarget() {
        let below = ProgressMath.numericFraction(direction: .increase, start: 10, current: 0, target: 20)
        let above = ProgressMath.numericFraction(direction: .increase, start: 10, current: 40, target: 20)
        XCTAssertEqual(below ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(above ?? -1, 1, accuracy: 0.0001)
    }

    func testDecreaseProgress() {
        let value = ProgressMath.numericFraction(direction: .decrease, start: 200, current: 190, target: 180)
        XCTAssertEqual(value ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertFalse(ProgressMath.numericTargetReached(direction: .decrease, start: 200, current: 190, target: 180))
        XCTAssertTrue(ProgressMath.numericTargetReached(direction: .decrease, start: 200, current: 170, target: 180))
    }

    func testEqualStartAndTargetStaysUnset() {
        XCTAssertNil(ProgressMath.numericFraction(direction: .increase, start: 10, current: 10, target: 10))
        XCTAssertNil(ProgressMath.numericFraction(direction: .decrease, start: 10, current: 8, target: 10))
        XCTAssertFalse(ProgressMath.numericTargetReached(direction: .increase, start: 10, current: 10, target: 10))
    }

    func testWrongDirectionStaysUnset() {
        XCTAssertNil(ProgressMath.numericFraction(direction: .increase, start: 50, current: 40, target: 30))
        XCTAssertNil(ProgressMath.numericFraction(direction: .decrease, start: 30, current: 40, target: 50))
    }

    func testEmptyMilestoneIsZeroAndNotComplete() {
        XCTAssertEqual(ProgressMath.milestoneFraction(completed: 0, total: 0), 0)
        XCTAssertFalse(ProgressMath.milestoneIsComplete(completed: 0, total: 0))
        XCTAssertTrue(ProgressMath.milestoneIsComplete(completed: 2, total: 2))
        XCTAssertEqual(ProgressMath.milestoneFraction(completed: 1, total: 4), 0.25, accuracy: 0.0001)
    }

    func testRatioAvoidsDivideByZero() {
        XCTAssertEqual(ProgressMath.ratio(completed: 1, expected: 0), 0)
        XCTAssertEqual(ProgressMath.ratio(completed: 3, expected: 2), 1)
    }
}

final class HabitPeriodTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    func testDailyMissedDayLowersCurrentWeekOnly() {
        let now = date(2026, 1, 7, 15)
        let monday = date(2026, 1, 5, 9)
        let schedule = HabitSchedule(frequency: .daily, weekdayMask: 0, weeklyQuota: 3)
        let snapshot = HabitPeriod.current(schedule: schedule, logDates: [monday], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.completed, 1)
        XCTAssertEqual(snapshot.expected, 4)
        XCTAssertEqual(snapshot.fraction, 0.25, accuracy: 0.0001)

        let marks = HabitPeriod.weekMarks(schedule: schedule, logDates: [monday], now: now, calendar: calendar)
        XCTAssertEqual(marks.map(\.state), [.open, .logged, .open, .open, .later, .later, .later])
    }

    func testWeekdayScheduleIgnoresUnselectedDays() {
        let now = date(2026, 1, 7, 15)
        let monday = date(2026, 1, 5, 9)
        let schedule = HabitSchedule(frequency: .weekdays, weekdayMask: WeekdayMask.weekdays, weeklyQuota: 3)
        let snapshot = HabitPeriod.current(schedule: schedule, logDates: [monday], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.completed, 1)
        XCTAssertEqual(snapshot.expected, 3)
    }

    func testWeeklyQuotaCapsTheRatio() {
        let now = date(2026, 1, 7, 15)
        let logs = [date(2026, 1, 4, 8), date(2026, 1, 5, 8), date(2026, 1, 6, 8)]
        let schedule = HabitSchedule(frequency: .weeklyQuota, weekdayMask: 0, weeklyQuota: 3)
        let snapshot = HabitPeriod.current(schedule: schedule, logDates: logs, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.completed, 3)
        XCTAssertEqual(snapshot.expected, 3)
        XCTAssertEqual(snapshot.fraction, 1, accuracy: 0.0001)
        XCTAssertEqual(
            HabitPeriod.validationError(schedule: schedule, existingLogDays: logs, day: now, now: now, calendar: calendar),
            .quotaFilled
        )
    }

    func testLogRules() {
        let now = date(2026, 1, 7, 15)
        let schedule = HabitSchedule(frequency: .daily, weekdayMask: 0, weeklyQuota: 3)
        XCTAssertEqual(
            HabitPeriod.validationError(schedule: schedule, existingLogDays: [], day: date(2026, 1, 8, 8), now: now, calendar: calendar),
            .future
        )
        XCTAssertEqual(
            HabitPeriod.validationError(schedule: schedule, existingLogDays: [now], day: now, now: now, calendar: calendar),
            .alreadyLogged
        )
        let weekdays = HabitSchedule(frequency: .weekdays, weekdayMask: WeekdayMask.weekdays, weeklyQuota: 3)
        XCTAssertEqual(
            HabitPeriod.validationError(schedule: weekdays, existingLogDays: [], day: date(2026, 1, 4, 8), now: now, calendar: calendar),
            .notScheduledThatDay
        )
    }

    func testPreviousWeekUsesTheWholeWeek() {
        let now = date(2026, 1, 7, 15)
        let lastSunday = date(2025, 12, 28, 8)
        let schedule = HabitSchedule(frequency: .daily, weekdayMask: 0, weeklyQuota: 3)
        let previous = HabitPeriod.previous(schedule: schedule, logDates: [lastSunday], now: now, calendar: calendar)
        XCTAssertEqual(previous[0].expected, 7)
        XCTAssertEqual(previous[0].completed, 1)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: parts)!
    }
}

final class ReminderSchedulingTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    func testOneShotPastAndFuture() {
        let now = date(2026, 1, 7, 15, 0)
        XCTAssertNil(ReminderScheduling.nextFireDate(
            fireOn: date(2026, 1, 6, 0, 0), hour: 9, minute: 0, weekday: 4, recurrence: .none, now: now, calendar: calendar
        ))
        let next = ReminderScheduling.nextFireDate(
            fireOn: date(2026, 1, 8, 0, 0), hour: 9, minute: 30, weekday: 5, recurrence: .none, now: now, calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 1, 8, 9, 30))
    }

    func testDailyRollsForwardAfterTheTimeHasPassed() {
        let now = date(2026, 1, 7, 15, 0)
        XCTAssertEqual(
            ReminderScheduling.nextFireDate(fireOn: now, hour: 18, minute: 0, weekday: 4, recurrence: .daily, now: now, calendar: calendar),
            date(2026, 1, 7, 18, 0)
        )
        XCTAssertEqual(
            ReminderScheduling.nextFireDate(fireOn: now, hour: 10, minute: 0, weekday: 4, recurrence: .daily, now: now, calendar: calendar),
            date(2026, 1, 8, 10, 0)
        )
    }

    func testWeeklyUsesTheStoredWeekday() {
        let now = date(2026, 1, 7, 15, 0)
        XCTAssertEqual(
            ReminderScheduling.nextFireDate(fireOn: now, hour: 9, minute: 0, weekday: 2, recurrence: .weekly, now: now, calendar: calendar),
            date(2026, 1, 12, 9, 0)
        )
    }

    func testMonthlyClampsShortMonths() {
        let february = date(2026, 2, 1, 0, 0)
        XCTAssertEqual(
            ReminderScheduling.nextFireDate(
                fireOn: date(2026, 1, 31, 0, 0), hour: 9, minute: 0, weekday: 1, recurrence: .monthly, now: february, calendar: calendar
            ),
            date(2026, 2, 28, 9, 0)
        )
        let lateFebruary = date(2026, 2, 28, 23, 0)
        XCTAssertEqual(
            ReminderScheduling.nextFireDate(
                fireOn: date(2026, 1, 31, 0, 0), hour: 9, minute: 0, weekday: 1, recurrence: .monthly, now: lateFebruary, calendar: calendar
            ),
            date(2026, 3, 31, 9, 0)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        parts.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: parts)!
    }
}

final class GoalValidationTests: XCTestCase {
    func testTitleAndHabitRules() {
        var draft = GoalDraft()
        draft.title = "   "
        XCTAssertEqual(GoalValidation.message(for: draft), "Add a title.")
        draft.title = "Read"
        draft.type = .habit
        draft.habitFrequency = .weekdays
        draft.weekdayMask = 0
        XCTAssertEqual(GoalValidation.message(for: draft), "Choose at least one day.")
        draft.type = .numeric
        XCTAssertEqual(GoalValidation.message(for: draft), "Add a start and a target.")
        draft.numericStart = 10
        draft.numericTarget = 10
        XCTAssertNil(GoalValidation.message(for: draft))
        XCTAssertNotNil(GoalValidation.hint(for: draft))
    }

    func testLinkAndNumberParsing() {
        XCTAssertEqual(LinkURL.normalize("example.com"), "https://example.com")
        XCTAssertEqual(LinkURL.normalize("https://example.com/a"), "https://example.com/a")
        XCTAssertNil(LinkURL.normalize(" "))
        XCTAssertNil(LinkURL.normalize("not a url"))
        XCTAssertEqual(NumberParsing.double(from: "10.5"), 10.5)
        XCTAssertNil(NumberParsing.double(from: "abc"))
    }

    func testCheckInDueAndPastDue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wednesday = ReminderScheduling.nextFireDate(
            fireOn: Date(), hour: 0, minute: 0, weekday: 1, recurrence: .none, now: .distantPast, calendar: calendar
        )
        _ = wednesday
        let now = date(calendar, 2026, 1, 7)
        XCTAssertTrue(CheckInDue.isDue(enabled: true, weekday: 4, hasSessionOnDay: false, now: now, calendar: calendar))
        XCTAssertFalse(CheckInDue.isDue(enabled: true, weekday: 4, hasSessionOnDay: true, now: now, calendar: calendar))
        XCTAssertFalse(CheckInDue.isDue(enabled: false, weekday: 4, hasSessionOnDay: false, now: now, calendar: calendar))
        XCTAssertFalse(DueDate.isPast(now, now: now, calendar: calendar))
        XCTAssertTrue(DueDate.isPast(date(calendar, 2026, 1, 6), now: now, calendar: calendar))
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts)!
    }
}
