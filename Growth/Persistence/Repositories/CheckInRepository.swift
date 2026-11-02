import Foundation
import SwiftData

struct CheckInDraftItem: Identifiable, Equatable {
    var id: UUID
    var goalID: UUID
    var goalTitle: String
    var feeling: Feeling?
    var whatHappened: String = ""
    var whatWillChange: String = ""
    var skipped: Bool = false
}

@MainActor
struct CheckInRepository {
    let context: ModelContext

    func schedule() -> CheckInSchedule {
        if let existing = (try? context.fetch(FetchDescriptor<CheckInSchedule>()))?.first {
            return existing
        }
        let schedule = CheckInSchedule()
        context.insert(schedule)
        try? StoreSaving.save(context)
        return schedule
    }

    func updateSchedule(_ schedule: CheckInSchedule, weekday: Int, hour: Int, minute: Int, enabled: Bool) throws {
        schedule.weekday = weekday
        schedule.hour = hour
        schedule.minute = minute
        schedule.enabled = enabled
        schedule.updatedAt = .now
        let reminder = schedule.reminder ?? Reminder()
        if schedule.reminder == nil {
            context.insert(reminder)
            schedule.reminder = reminder
        }
        reminder.title = "Weekly check-in"
        reminder.body = "A short pass over the goals you're working on."
        reminder.kind = .checkIn
        reminder.recurrence = .weekly
        reminder.weekday = weekday
        reminder.hour = hour
        reminder.minute = minute
        reminder.fireOn = .now
        reminder.enabled = enabled
        reminder.goal = nil
        reminder.updatedAt = .now
        try StoreSaving.save(context)
    }

    func hasSession(on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        let sessions = (try? context.fetch(FetchDescriptor<CheckInSession>())) ?? []
        return sessions.contains { $0.createdAt >= start && $0.createdAt < end }
    }

    func saveSession(_ drafts: [CheckInDraftItem], goals: [Goal]) {
        let session = CheckInSession()
        session.completedAt = .now
        context.insert(session)
        let goalsByID = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        for draft in drafts {
            let item = CheckInItem()
            item.goalTitle = draft.goalTitle
            item.feeling = draft.skipped ? nil : draft.feeling
            item.whatHappened = draft.whatHappened.trimmingCharacters(in: .whitespacesAndNewlines)
            item.whatWillChange = draft.whatWillChange.trimmingCharacters(in: .whitespacesAndNewlines)
            item.skipped = draft.skipped
            item.goal = goalsByID[draft.goalID]
            item.session = session
            context.insert(item)
        }
        try? StoreSaving.save(context)
    }
}

@MainActor
struct RecalibrationRepository {
    let context: ModelContext

    @discardableResult
    func finish(goal: Goal, situation: String, reflectionNote: String, startedAt: Date) -> Recalibration {
        let record = Recalibration()
        record.situation = situation.trimmingCharacters(in: .whitespacesAndNewlines)
        record.reflectionNote = reflectionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        record.goalTitle = goal.title
        record.goal = goal
        context.insert(record)
        let event = ActivityLog.record(
            in: context,
            goal: goal,
            type: .recalibrated,
            summary: ActivitySummary.recalibrated(),
            detail: record.situation
        )
        let prior = events(for: goal, since: startedAt).map(\.id)
        var ids = prior
        if !ids.contains(event.id) {
            ids.append(event.id)
        }
        record.eventIDs = ids
        goal.updatedAt = .now
        try? StoreSaving.save(context)
        return record
    }

    func events(for goal: Goal, since: Date) -> [ActivityEvent] {
        (goal.activityEvents ?? [])
            .filter { $0.createdAt >= since }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func events(for goal: Goal) -> [ActivityEvent] {
        (goal.activityEvents ?? []).sorted { $0.createdAt > $1.createdAt }
    }
}
