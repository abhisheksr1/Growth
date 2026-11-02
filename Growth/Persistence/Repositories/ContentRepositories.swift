import Foundation
import SwiftData

@MainActor
struct ReminderRepository {
    let context: ModelContext

    @discardableResult
    func create(
        goal: Goal?,
        checkpoint: Checkpoint?,
        title: String,
        body: String,
        fireOn: Date,
        hour: Int,
        minute: Int,
        weekday: Int,
        recurrence: ReminderRecurrence,
        enabled: Bool,
        kind: ReminderKind = .goal
    ) throws -> Reminder {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalid("Add a reminder title.") }
        let reminder = Reminder()
        reminder.title = trimmed
        reminder.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.fireOn = fireOn
        reminder.hour = hour
        reminder.minute = minute
        reminder.weekday = weekday
        reminder.recurrence = recurrence
        reminder.enabled = enabled
        reminder.kind = kind
        reminder.goal = goal
        reminder.checkpoint = checkpoint
        context.insert(reminder)
        if let goal {
            goal.updatedAt = .now
            ActivityLog.record(
                in: context,
                goal: goal,
                type: .reminderChanged,
                summary: ActivitySummary.reminder(trimmed, change: "Added"),
                after: trimmed
            )
        }
        try StoreSaving.save(context)
        return reminder
    }

    func update(
        _ reminder: Reminder,
        title: String,
        body: String,
        fireOn: Date,
        hour: Int,
        minute: Int,
        weekday: Int,
        recurrence: ReminderRecurrence,
        enabled: Bool
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalid("Add a reminder title.") }
        reminder.title = trimmed
        reminder.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.fireOn = fireOn
        reminder.hour = hour
        reminder.minute = minute
        reminder.weekday = weekday
        reminder.recurrence = recurrence
        reminder.enabled = enabled
        reminder.updatedAt = .now
        if let goal = reminder.goal {
            goal.updatedAt = .now
            ActivityLog.record(
                in: context,
                goal: goal,
                type: .reminderChanged,
                summary: ActivitySummary.reminder(trimmed, change: "Updated"),
                after: trimmed
            )
        }
        try StoreSaving.save(context)
    }

    func softDelete(_ reminder: Reminder) {
        reminder.deletedAt = .now
        reminder.enabled = false
        reminder.updatedAt = .now
        if let goal = reminder.goal {
            goal.updatedAt = .now
            ActivityLog.record(
                in: context,
                goal: goal,
                type: .reminderChanged,
                summary: ActivitySummary.reminder(reminder.title, change: "Removed"),
                detail: reminder.title
            )
        }
        try? StoreSaving.save(context)
    }

    func upcoming(now: Date = .now, calendar: Calendar = .current, limit: Int? = nil) -> [Reminder] {
        let rows = ((try? context.fetch(FetchDescriptor<Reminder>())) ?? [])
            .filter { reminder in
                guard reminder.deletedAt == nil, reminder.enabled else { return false }
                if let goal = reminder.goal, goal.deletedAt != nil || goal.silencesReminders {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                let left = lhs.schedulingSnapshot.flatMap { ReminderScheduling.nextFireDate($0, now: now, calendar: calendar) }
                let right = rhs.schedulingSnapshot.flatMap { ReminderScheduling.nextFireDate($0, now: now, calendar: calendar) }
                switch (left, right) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.title < rhs.title
                }
            }
        if let limit { return Array(rows.prefix(limit)) }
        return rows
    }
}

@MainActor
struct JournalRepository {
    let context: ModelContext

    @discardableResult
    func save(existing: JournalEntry?, title: String, body: String, goals: [Goal]) throws -> JournalEntry {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else {
            throw RepositoryError.invalid("Write a title or a few lines.")
        }
        let entry = existing ?? JournalEntry()
        if existing == nil {
            context.insert(entry)
        }
        entry.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
        entry.body = trimmedBody
        entry.goals = goals.filter { $0.deletedAt == nil }
        entry.updatedAt = .now
        try StoreSaving.save(context)
        return entry
    }

    func softDelete(_ entry: JournalEntry) {
        entry.deletedAt = .now
        entry.updatedAt = .now
        entry.goals = []
        try? StoreSaving.save(context)
    }

    static func filtered(_ entries: [JournalEntry], search: String) -> [JournalEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries
            .filter { $0.deletedAt == nil }
            .filter { entry in
                guard !query.isEmpty else { return true }
                return entry.title.localizedStandardContains(query) || entry.body.localizedStandardContains(query)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

@MainActor
struct ReflectionRepository {
    let context: ModelContext

    @discardableResult
    func create(
        goal: Goal,
        feeling: Feeling,
        expected: String,
        happened: String,
        worked: String,
        inTheWay: String,
        learned: String,
        nextChange: String
    ) -> Reflection {
        let reflection = Reflection()
        reflection.feeling = feeling
        reflection.expectedText = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        reflection.happenedText = happened.trimmingCharacters(in: .whitespacesAndNewlines)
        reflection.workedText = worked.trimmingCharacters(in: .whitespacesAndNewlines)
        reflection.inTheWayText = inTheWay.trimmingCharacters(in: .whitespacesAndNewlines)
        reflection.learnedText = learned.trimmingCharacters(in: .whitespacesAndNewlines)
        reflection.nextChangeText = nextChange.trimmingCharacters(in: .whitespacesAndNewlines)
        reflection.goalTitle = goal.title
        reflection.goal = goal
        context.insert(reflection)
        goal.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .reflectionAdded,
            summary: ActivitySummary.reflection(),
            detail: feeling.title
        )
        try? StoreSaving.save(context)
        return reflection
    }

    func softDelete(_ reflection: Reflection) {
        reflection.deletedAt = .now
        reflection.updatedAt = .now
        try? StoreSaving.save(context)
    }
}
