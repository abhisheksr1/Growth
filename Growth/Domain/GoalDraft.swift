import Foundation

struct GoalDraft: Equatable, Sendable {
    var title: String = ""
    var details: String = ""
    var notes: String = ""
    var type: GoalType = .milestone
    var category: String = ""
    var startDate: Date = .now
    var hasTargetDate: Bool = false
    var targetDate: Date = .now
    var numericStart: Double?
    var numericTarget: Double?
    var numericUnit: String = ""
    var numericDirection: NumericDirection = .increase
    var habitFrequency: HabitFrequency = .daily
    var weekdayMask: Int = WeekdayMask.weekdays
    var weeklyQuota: Int = 3

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedTargetDate: Date? {
        hasTargetDate ? targetDate : nil
    }
}

enum GoalValidation {
    /// A blocking reason, when the draft cannot be saved.
    static func message(for draft: GoalDraft) -> String? {
        if draft.trimmedTitle.isEmpty {
            return "Add a title."
        }
        switch draft.type {
        case .milestone, .project, .oneTime:
            return nil
        case .numeric:
            if draft.numericStart == nil || draft.numericTarget == nil {
                return "Add a start and a target."
            }
            return nil
        case .habit:
            switch draft.habitFrequency {
            case .daily:
                return nil
            case .weekdays:
                return draft.weekdayMask == 0 ? "Choose at least one day." : nil
            case .weeklyQuota:
                return (1...7).contains(draft.weeklyQuota) ? nil : "Choose a quota from 1 to 7."
            }
        }
    }

    /// Guidance that does not block saving. Equal start and target is allowed; progress stays unset.
    static func hint(for draft: GoalDraft) -> String? {
        guard draft.type == .numeric, let start = draft.numericStart, let target = draft.numericTarget else {
            return nil
        }
        if start == target {
            return "Start and target are the same, so progress stays unset until they differ."
        }
        if draft.numericDirection == .increase, target < start {
            return "For an increase, the target should be higher than the start."
        }
        if draft.numericDirection == .decrease, target > start {
            return "For a decrease, the target should be lower than the start."
        }
        return nil
    }
}
