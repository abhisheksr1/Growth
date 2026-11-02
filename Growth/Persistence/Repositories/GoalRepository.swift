import Foundation
import SwiftData

@MainActor
struct GoalRepository {
    let context: ModelContext

    static func filtered(_ goals: [Goal], status: GoalStatus?, search: String) -> [Goal] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return goals.filter { goal in
            guard goal.deletedAt == nil else { return false }
            if let status, goal.status != status { return false }
            guard !query.isEmpty else { return true }
            return goal.title.localizedStandardContains(query) || goal.category.localizedStandardContains(query)
        }
    }

    static func active(_ goals: [Goal]) -> [Goal] {
        goals.filter { $0.deletedAt == nil && $0.status.isActiveWork }
    }

    static func homeSorted(_ goals: [Goal], now: Date = .now, calendar: Calendar = .current) -> [Goal] {
        active(goals).sorted { lhs, rhs in
            let leftPast = lhs.isPastDue(now: now, calendar: calendar)
            let rightPast = rhs.isPastDue(now: now, calendar: calendar)
            if leftPast != rightPast { return leftPast }
            switch (lhs.targetDate, rhs.targetDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    func allGoals() -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.filter { $0.deletedAt == nil }
    }

    @discardableResult
    func create(_ draft: GoalDraft) throws -> Goal {
        if let message = GoalValidation.message(for: draft) {
            throw RepositoryError.invalid(message)
        }
        let goal = Goal()
        context.insert(goal)
        apply(draft, to: goal, isNew: true)
        goal.status = .notStarted
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .created,
            summary: ActivitySummary.created(title: goal.title)
        )
        try StoreSaving.save(context)
        return goal
    }

    func update(_ goal: Goal, draft: GoalDraft) throws {
        if let message = GoalValidation.message(for: draft) {
            throw RepositoryError.invalid(message)
        }
        let previousTitle = goal.title
        let previousTarget = goal.targetDate
        let previousStart = goal.startDate
        let previousNumericTarget = goal.numericTarget
        apply(draft, to: goal, isNew: false)
        if previousTitle != goal.title {
            ActivityLog.record(
                in: context,
                goal: goal,
                type: .roadmapEdited,
                summary: "Renamed to \(goal.title)",
                before: previousTitle,
                after: goal.title
            )
        }
        if previousStart != goal.startDate || previousTarget != goal.targetDate {
            ActivityLog.record(
                in: context,
                goal: goal,
                type: .roadmapEdited,
                summary: "Updated dates",
                before: dateLabel(previousTarget),
                after: dateLabel(goal.targetDate)
            )
        }
        if previousNumericTarget != goal.numericTarget {
            ActivityLog.record(
                in: context,
                goal: goal,
                type: .roadmapEdited,
                summary: "Updated the target",
                before: previousNumericTarget.map(DecimalText.string),
                after: goal.numericTarget.map(DecimalText.string)
            )
        }
        try StoreSaving.save(context)
    }

    func setStatus(_ goal: Goal, to status: GoalStatus) {
        let before = goal.status
        guard before != status else { return }
        goal.status = status
        goal.updatedAt = .now
        let type: ActivityEventType
        switch status {
        case .paused:
            type = .paused
        case .archived:
            type = .archived
        case .completed:
            type = .completed
        case .inProgress where before == .paused || before == .archived:
            type = .resumed
        default:
            type = .statusChanged
        }
        ActivityLog.record(
            in: context,
            goal: goal,
            type: type,
            summary: ActivitySummary.status(from: before, to: status),
            before: before.title,
            after: status.title
        )
        try? StoreSaving.save(context)
    }

    func softDelete(_ goal: Goal) {
        let now = Date()
        goal.deletedAt = now
        goal.updatedAt = now
        for entry in goal.journalEntries ?? [] {
            entry.goals = (entry.goals ?? []).filter { $0.id != goal.id }
            entry.updatedAt = now
        }
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .deleted,
            summary: "Deleted \(goal.title)",
            detail: goal.title
        )
        try? StoreSaving.save(context)
    }

    func enablePlan(_ goal: Goal) {
        guard goal.type == .numeric else { return }
        goal.allowsPlan = true
        goal.updatedAt = .now
        try? StoreSaving.save(context)
    }

    /// Moves a not-started goal into progress the first time real work is recorded.
    func noteProgressStarted(_ goal: Goal) {
        guard goal.status == .notStarted else { return }
        let before = goal.status
        goal.status = .inProgress
        goal.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .statusChanged,
            summary: ActivitySummary.status(from: before, to: .inProgress),
            before: before.title,
            after: GoalStatus.inProgress.title
        )
    }

    private func apply(_ draft: GoalDraft, to goal: Goal, isNew: Bool) {
        goal.title = draft.trimmedTitle
        goal.details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.startDate = draft.startDate
        goal.targetDate = draft.resolvedTargetDate
        goal.updatedAt = .now
        if isNew {
            goal.type = draft.type
            goal.allowsPlan = draft.type == .milestone || draft.type == .project
        }
        if goal.type == .numeric {
            goal.numericStart = draft.numericStart
            goal.numericTarget = draft.numericTarget
            goal.numericUnit = draft.numericUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            goal.numericDirection = draft.numericDirection
            if goal.latestProgressEntry == nil {
                goal.numericCurrent = draft.numericStart
            }
        }
        if goal.type == .habit {
            goal.habitFrequency = draft.habitFrequency
            goal.weekdayMask = draft.weekdayMask
            goal.weeklyQuota = min(max(draft.weeklyQuota, 1), 7)
        }
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "No target date" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
