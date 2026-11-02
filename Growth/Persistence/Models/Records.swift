import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var title: String = ""
    var details: String = ""
    var notes: String = ""
    var typeRaw: String = GoalType.milestone.rawValue
    var statusRaw: String = GoalStatus.notStarted.rawValue
    var category: String = ""
    var startDate: Date = Date()
    var targetDate: Date?
    var allowsPlan: Bool = false
    var numericTarget: Double?
    var numericStart: Double?
    var numericCurrent: Double?
    var numericUnit: String = ""
    var numericDirectionRaw: String = NumericDirection.increase.rawValue
    var habitFrequencyRaw: String = HabitFrequency.daily.rawValue
    var weekdayMask: Int = WeekdayMask.weekdays
    var weeklyQuota: Int = 3

    @Relationship(deleteRule: .cascade, inverse: \Phase.goal)
    var phases: [Phase]? = []

    @Relationship(deleteRule: .cascade, inverse: \ProgressEntry.goal)
    var progressEntries: [ProgressEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \HabitLog.goal)
    var habitLogs: [HabitLog]? = []

    @Relationship(deleteRule: .nullify, inverse: \Reminder.goal)
    var reminders: [Reminder]? = []

    @Relationship(deleteRule: .nullify, inverse: \Reflection.goal)
    var reflections: [Reflection]? = []

    @Relationship(deleteRule: .nullify, inverse: \ActivityEvent.goal)
    var activityEvents: [ActivityEvent]? = []

    @Relationship(deleteRule: .nullify, inverse: \Recalibration.goal)
    var recalibrations: [Recalibration]? = []

    @Relationship(deleteRule: .nullify, inverse: \JournalEntry.goals)
    var journalEntries: [JournalEntry]? = []

    @Relationship(deleteRule: .nullify, inverse: \CheckInItem.goal)
    var checkInItems: [CheckInItem]? = []

    init() {}
}

@Model
final class Phase {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var title: String = ""
    var notes: String = ""
    var sortIndex: Int = 0
    var goal: Goal?

    @Relationship(deleteRule: .cascade, inverse: \Checkpoint.phase)
    var checkpoints: [Checkpoint]? = []

    @Relationship(deleteRule: .cascade, inverse: \ResourceLink.phase)
    var resources: [ResourceLink]? = []

    init() {}
}

@Model
final class Checkpoint {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var title: String = ""
    var notes: String = ""
    var sortIndex: Int = 0
    var targetDate: Date?
    var completedAt: Date?
    var phase: Phase?

    @Relationship(deleteRule: .nullify, inverse: \ResourceLink.checkpoint)
    var resources: [ResourceLink]? = []

    @Relationship(deleteRule: .nullify, inverse: \Reminder.checkpoint)
    var reminders: [Reminder]? = []

    init() {}
}

@Model
final class ResourceLink {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var title: String = ""
    var urlString: String = ""
    var note: String = ""
    var phase: Phase?
    var checkpoint: Checkpoint?

    init() {}
}

@Model
final class ProgressEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var value: Double = 0
    var recordedAt: Date = Date()
    var note: String = ""
    var goal: Goal?

    init() {}
}

@Model
final class HabitLog {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var deletedAt: Date?
    var occurredOn: Date = Date()
    var note: String = ""
    var goal: Goal?

    init() {}
}

@Model
final class Reminder {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var title: String = ""
    var body: String = ""
    var fireOn: Date = Date()
    var hour: Int = 9
    var minute: Int = 0
    var weekday: Int = 2
    var recurrenceRaw: String = ReminderRecurrence.none.rawValue
    var enabled: Bool = true
    var kindRaw: String = ReminderKind.goal.rawValue
    var goal: Goal?
    var checkpoint: Checkpoint?
    var checkInSchedule: CheckInSchedule?

    init() {}
}

@Model
final class ActivityEvent {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var typeRaw: String = ActivityEventType.created.rawValue
    var summary: String = ""
    var snapshotJSON: String = "{}"
    var goalTitle: String = ""
    var goal: Goal?

    init() {}
}

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var title: String = ""
    var body: String = ""
    var goals: [Goal]? = []

    init() {}
}

@Model
final class Reflection {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var feelingRaw: String = Feeling.okay.rawValue
    var expectedText: String = ""
    var happenedText: String = ""
    var workedText: String = ""
    var inTheWayText: String = ""
    var learnedText: String = ""
    var nextChangeText: String = ""
    var goalTitle: String = ""
    var goal: Goal?

    init() {}
}

@Model
final class CheckInSchedule {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var weekday: Int = 2
    var hour: Int = 9
    var minute: Int = 0
    var enabled: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Reminder.checkInSchedule)
    var reminder: Reminder?

    init() {}
}

@Model
final class CheckInSession {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var completedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \CheckInItem.session)
    var items: [CheckInItem]? = []

    init() {}
}

@Model
final class CheckInItem {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var feelingRaw: String?
    var whatHappened: String = ""
    var whatWillChange: String = ""
    var skipped: Bool = false
    var goalTitle: String = ""
    var goal: Goal?
    var session: CheckInSession?

    init() {}
}

@Model
final class Recalibration {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var situation: String = ""
    var reflectionNote: String = ""
    var eventIDList: String = ""
    var goalTitle: String = ""
    var goal: Goal?

    init() {}
}
