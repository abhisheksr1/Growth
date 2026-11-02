import Foundation
import SwiftData

enum RepositoryError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

@MainActor
enum ActivityLog {
    @discardableResult
    static func record(
        in context: ModelContext,
        goal: Goal?,
        type: ActivityEventType,
        summary: String,
        before: String? = nil,
        after: String? = nil,
        detail: String? = nil
    ) -> ActivityEvent {
        let event = ActivityEvent()
        event.type = type
        event.summary = summary
        event.goalTitle = goal?.title ?? ""
        event.snapshotJSON = ActivitySnapshot(
            goalTitle: goal?.title ?? "",
            before: before,
            after: after,
            detail: detail
        ).jsonString()
        event.goal = goal
        context.insert(event)
        return event
    }
}

@MainActor
enum StoreSaving {
    static func save(_ context: ModelContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }
}
