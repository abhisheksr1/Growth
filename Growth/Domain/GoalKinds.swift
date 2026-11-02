import Foundation

enum GoalType: String, CaseIterable, Identifiable, Sendable {
    case milestone
    case project
    case numeric
    case habit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .milestone: "Milestone"
        case .project: "Project"
        case .numeric: "Number"
        case .habit: "Habit"
        }
    }

    var symbolName: String {
        switch self {
        case .milestone: "flag"
        case .project: "square.stack.3d.up"
        case .numeric: "number"
        case .habit: "repeat"
        }
    }

    var blurb: String {
        switch self {
        case .milestone:
            "A finish line made of phases and checkpoints."
        case .project:
            "The same plan as a milestone, for work that has a clear done."
        case .numeric:
            "A value that should rise or fall, with a history of each update."
        case .habit:
            "A quiet log of the days you show up. Missed days stay uneventful."
        }
    }
}

enum GoalStatus: String, CaseIterable, Identifiable, Sendable {
    case notStarted
    case inProgress
    case paused
    case completed
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .paused: "Paused"
        case .completed: "Complete"
        case .archived: "Archived"
        }
    }

    var symbolName: String {
        switch self {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        case .archived: "archivebox"
        }
    }

    /// Statuses that belong on Home.
    var isActiveWork: Bool {
        self == .notStarted || self == .inProgress
    }
}

enum NumericDirection: String, CaseIterable, Identifiable, Sendable {
    case increase
    case decrease

    var id: String { rawValue }

    var title: String {
        switch self {
        case .increase: "Increase"
        case .decrease: "Decrease"
        }
    }

    var footnote: String {
        switch self {
        case .increase: "Savings, books, distance."
        case .decrease: "Weight, debt, anything you want less of."
        }
    }
}

enum HabitFrequency: String, CaseIterable, Identifiable, Sendable {
    case daily
    case weekdays
    case weeklyQuota

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Specific days"
        case .weeklyQuota: "Times per week"
        }
    }
}

enum ReminderRecurrence: String, CaseIterable, Identifiable, Sendable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Doesn't repeat"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

enum ReminderKind: String, Sendable {
    case goal
    case checkIn
}

enum Feeling: String, CaseIterable, Identifiable, Sendable {
    case great
    case okay
    case behind
    case stuck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .great: "Great"
        case .okay: "Okay"
        case .behind: "Behind"
        case .stuck: "Stuck"
        }
    }

    var symbolName: String {
        switch self {
        case .great: "sun.max"
        case .okay: "cloud.sun"
        case .behind: "clock"
        case .stuck: "questionmark.circle"
        }
    }

    var wantsDeeperLook: Bool {
        self == .behind || self == .stuck
    }
}

enum ActivityEventType: String, CaseIterable, Sendable {
    case created
    case statusChanged
    case checkpointCompleted
    case checkpointReopened
    case progressUpdated
    case habitLogged
    case reminderChanged
    case reflectionAdded
    case roadmapEdited
    case recalibrated
    case paused
    case resumed
    case completed
    case archived
    case deleted

    var title: String {
        switch self {
        case .created: "Created"
        case .statusChanged: "Status"
        case .checkpointCompleted: "Checkpoint"
        case .checkpointReopened: "Checkpoint"
        case .progressUpdated: "Progress"
        case .habitLogged: "Habit"
        case .reminderChanged: "Reminder"
        case .reflectionAdded: "Reflection"
        case .roadmapEdited: "Plan"
        case .recalibrated: "Recalibrated"
        case .paused: "Paused"
        case .resumed: "Resumed"
        case .completed: "Complete"
        case .archived: "Archived"
        case .deleted: "Deleted"
        }
    }

    var symbolName: String {
        switch self {
        case .created: "plus.circle"
        case .statusChanged: "arrow.triangle.2.circlepath"
        case .checkpointCompleted: "checkmark.circle"
        case .checkpointReopened: "arrow.uturn.backward.circle"
        case .progressUpdated: "chart.line.uptrend.xyaxis"
        case .habitLogged: "repeat"
        case .reminderChanged: "bell"
        case .reflectionAdded: "text.quote"
        case .roadmapEdited: "map"
        case .recalibrated: "arrow.triangle.branch"
        case .paused: "pause.circle"
        case .resumed: "play.circle"
        case .completed: "flag.checkered"
        case .archived: "archivebox"
        case .deleted: "trash"
        }
    }
}
