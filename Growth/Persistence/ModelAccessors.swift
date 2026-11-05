import Foundation

extension Goal {
    var type: GoalType {
        get { GoalType(rawValue: typeRaw) ?? .milestone }
        set { typeRaw = newValue.rawValue }
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var numericDirection: NumericDirection {
        get { NumericDirection(rawValue: numericDirectionRaw) ?? .increase }
        set { numericDirectionRaw = newValue.rawValue }
    }

    var habitFrequency: HabitFrequency {
        get { HabitFrequency(rawValue: habitFrequencyRaw) ?? .daily }
        set { habitFrequencyRaw = newValue.rawValue }
    }

    var habitSchedule: HabitSchedule {
        HabitSchedule(frequency: habitFrequency, weekdayMask: weekdayMask, weeklyQuota: weeklyQuota)
    }

    var silencesReminders: Bool {
        deletedAt != nil || status == .paused || status == .archived
    }

    var showsPlan: Bool {
        switch type {
        case .milestone, .project:
            true
        case .numeric:
            allowsPlan
        case .habit, .oneTime:
            false
        }
    }

    var sortedPhases: [Phase] {
        (phases ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    var allCheckpoints: [Checkpoint] {
        sortedPhases.flatMap(\.sortedCheckpoints)
    }

    var latestProgressEntry: ProgressEntry? {
        (progressEntries ?? []).sorted { lhs, rhs in
            if lhs.recordedAt == rhs.recordedAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.recordedAt < rhs.recordedAt
        }.last
    }

    var resolvedCurrent: Double? {
        latestProgressEntry?.value ?? numericCurrent ?? numericStart
    }

    var activeHabitLogs: [HabitLog] {
        (habitLogs ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.occurredOn > $1.occurredOn }
    }

    var activeReminders: [Reminder] {
        (reminders ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var activeReflections: [Reflection] {
        (reflections ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var linkedJournal: [JournalEntry] {
        (journalEntries ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeRecalibrations: [Recalibration] {
        (recalibrations ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func isPastDue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        if let targetDate, DueDate.isPast(targetDate, now: now, calendar: calendar) {
            return true
        }
        return allCheckpoints.contains { checkpoint in
            guard checkpoint.completedAt == nil, let targetDate = checkpoint.targetDate else { return false }
            return DueDate.isPast(targetDate, now: now, calendar: calendar)
        }
    }

    var suggestsCompletion: Bool {
        switch type {
        case .milestone, .project:
            let checks = allCheckpoints
            let done = checks.filter { $0.completedAt != nil }.count
            return ProgressMath.milestoneIsComplete(completed: done, total: checks.count)
        case .numeric:
            guard let start = numericStart, let current = resolvedCurrent, let target = numericTarget else {
                return false
            }
            return ProgressMath.numericTargetReached(
                direction: numericDirection,
                start: start,
                current: current,
                target: target
            )
        case .habit, .oneTime:
            return false
        }
    }

    var canPromptCompletion: Bool {
        status == .notStarted || status == .inProgress
    }
}

extension Phase {
    var sortedCheckpoints: [Checkpoint] {
        (checkpoints ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    var activeResources: [ResourceLink] {
        (resources ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

extension Checkpoint {
    var activeResources: [ResourceLink] {
        (resources ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var activeReminders: [Reminder] {
        (reminders ?? []).filter { $0.deletedAt == nil }
    }
}

extension ResourceLink {
    var url: URL? {
        guard let normalized = LinkURL.normalize(urlString) else { return nil }
        return URL(string: normalized)
    }
}

extension Reminder {
    var recurrence: ReminderRecurrence {
        get { ReminderRecurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRaw) ?? .goal }
        set { kindRaw = newValue.rawValue }
    }

    var schedulingSnapshot: ReminderSnapshot? {
        guard deletedAt == nil else { return nil }
        if let goal, goal.deletedAt != nil { return nil }
        return ReminderSnapshot(
            id: id,
            kind: kind,
            goalID: goal?.id,
            title: title,
            body: body,
            fireOn: fireOn,
            hour: hour,
            minute: minute,
            weekday: weekday,
            recurrence: recurrence,
            enabled: enabled,
            silenced: goal?.silencesReminders ?? false
        )
    }
}

extension Reflection {
    var feeling: Feeling {
        get { Feeling(rawValue: feelingRaw) ?? .okay }
        set { feelingRaw = newValue.rawValue }
    }
}

extension CheckInItem {
    var feeling: Feeling? {
        get { feelingRaw.flatMap(Feeling.init(rawValue:)) }
        set { feelingRaw = newValue?.rawValue }
    }
}

extension ActivityEvent {
    var type: ActivityEventType {
        get { ActivityEventType(rawValue: typeRaw) ?? .created }
        set { typeRaw = newValue.rawValue }
    }

    var snapshot: ActivitySnapshot? {
        ActivitySnapshot.decode(snapshotJSON)
    }
}

extension Recalibration {
    var eventIDs: [UUID] {
        get {
            eventIDList.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        }
        set {
            eventIDList = newValue.map(\.uuidString).joined(separator: ",")
        }
    }
}

extension GoalDraft {
    init(goal: Goal) {
        title = goal.title
        details = goal.details
        notes = goal.notes
        type = goal.type
        category = goal.category
        startDate = goal.startDate
        if let targetDate = goal.targetDate {
            hasTargetDate = true
            self.targetDate = targetDate
        } else {
            hasTargetDate = false
            targetDate = .now
        }
        numericStart = goal.numericStart
        numericTarget = goal.numericTarget
        numericUnit = goal.numericUnit
        numericDirection = goal.numericDirection
        habitFrequency = goal.habitFrequency
        weekdayMask = goal.weekdayMask
        weeklyQuota = goal.weeklyQuota
    }
}
