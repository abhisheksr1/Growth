import Foundation

struct GoalProgressPresentation: Equatable {
    var fraction: Double?
    var caption: String
    var note: String?
}

extension Goal {
    func progressPresentation(now: Date = .now, calendar: Calendar = .current) -> GoalProgressPresentation {
        switch type {
        case .milestone, .project:
            let checks = allCheckpoints
            let done = checks.filter { $0.completedAt != nil }.count
            let fraction = ProgressMath.milestoneFraction(completed: done, total: checks.count)
            if checks.isEmpty {
                return GoalProgressPresentation(
                    fraction: 0,
                    caption: "0%",
                    note: "Add a phase when you know the first step."
                )
            }
            return GoalProgressPresentation(
                fraction: fraction,
                caption: "\(done) of \(checks.count) checkpoints",
                note: nil
            )
        case .numeric:
            guard let start = numericStart, let target = numericTarget else {
                return GoalProgressPresentation(fraction: nil, caption: "Add a start and a target", note: nil)
            }
            let current = resolvedCurrent ?? start
            let fraction = ProgressMath.numericFraction(
                direction: numericDirection,
                start: start,
                current: current,
                target: target
            )
            let unit = numericUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentText = DecimalText.string(current)
            let targetText = DecimalText.string(target)
            let suffix = unit.isEmpty ? "" : " \(unit)"
            if fraction == nil {
                return GoalProgressPresentation(
                    fraction: nil,
                    caption: "\(currentText)\(suffix)",
                    note: "Progress stays unset until the start and target differ in the right direction."
                )
            }
            return GoalProgressPresentation(
                fraction: fraction,
                caption: "\(currentText) of \(targetText)\(suffix)",
                note: nil
            )
        case .habit:
            let dates = activeHabitLogs.map(\.occurredOn)
            let snapshot = HabitPeriod.current(
                schedule: habitSchedule,
                logDates: dates,
                now: now,
                calendar: calendar
            )
            let caption: String
            if habitFrequency == .weeklyQuota {
                caption = "\(snapshot.completed) of \(snapshot.expected) this week"
            } else if snapshot.expected == 0 {
                caption = "Nothing scheduled yet this week"
            } else {
                caption = "\(snapshot.completed) of \(snapshot.expected) so far this week"
            }
            return GoalProgressPresentation(fraction: snapshot.fraction, caption: caption, note: nil)
        }
    }
}
