import Foundation
import SwiftData

@MainActor
struct ProgressRepository {
    let context: ModelContext

    @discardableResult
    func addEntry(goal: Goal, value: Double, recordedAt: Date, note: String) throws -> ProgressEntry {
        guard goal.type == .numeric else {
            throw RepositoryError.invalid("Only number goals keep a value history.")
        }
        let entry = ProgressEntry()
        entry.value = value
        entry.recordedAt = recordedAt
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.goal = goal
        context.insert(entry)
        var pool = goal.progressEntries ?? []
        if pool.contains(where: { $0.id == entry.id }) == false {
            pool.append(entry)
        }
        let latest = pool.sorted { lhs, rhs in
            if lhs.recordedAt == rhs.recordedAt { return lhs.createdAt < rhs.createdAt }
            return lhs.recordedAt < rhs.recordedAt
        }.last
        goal.numericCurrent = latest?.value ?? value
        goal.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .progressUpdated,
            summary: ActivitySummary.progress(value: value, unit: goal.numericUnit),
            after: DecimalText.string(value),
            detail: entry.note.isEmpty ? nil : entry.note
        )
        GoalRepository(context: context).noteProgressStarted(goal)
        try StoreSaving.save(context)
        return entry
    }

    func history(_ goal: Goal) -> [ProgressEntry] {
        (goal.progressEntries ?? []).sorted { lhs, rhs in
            if lhs.recordedAt == rhs.recordedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.recordedAt > rhs.recordedAt
        }
    }
}

@MainActor
struct HabitRepository {
    let context: ModelContext

    func log(goal: Goal, on day: Date, note: String, now: Date = .now, calendar: Calendar = .current) throws {
        guard goal.type == .habit else {
            throw RepositoryError.invalid("Only habit goals take a daily log.")
        }
        let existing = goal.activeHabitLogs.map(\.occurredOn)
        if let error = HabitPeriod.validationError(
            schedule: goal.habitSchedule,
            existingLogDays: existing,
            day: day,
            now: now,
            calendar: calendar
        ) {
            throw error
        }
        let entry = HabitLog()
        entry.occurredOn = calendar.startOfDay(for: day)
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.goal = goal
        context.insert(entry)
        goal.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .habitLogged,
            summary: ActivitySummary.habit(on: entry.occurredOn, calendar: calendar),
            detail: entry.note.isEmpty ? nil : entry.note
        )
        GoalRepository(context: context).noteProgressStarted(goal)
        try StoreSaving.save(context)
    }
}
