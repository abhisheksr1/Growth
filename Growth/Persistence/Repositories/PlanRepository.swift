import Foundation
import SwiftData

enum PlanImportMode: Sendable {
    case replace
    case append
}

@MainActor
struct PlanRepository {
    let context: ModelContext

    @discardableResult
    func addPhase(to goal: Goal, title: String) throws -> Phase {
        switch goal.type {
        case .habit:
            throw RepositoryError.invalid("Habits don't use a roadmap.")
        case .oneTime:
            throw RepositoryError.invalid("One-time tasks don't use a roadmap.")
        case .milestone, .project, .numeric:
            break
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalid("Add a phase title.") }
        let phase = Phase()
        phase.title = trimmed
        phase.sortIndex = (goal.sortedPhases.map(\.sortIndex).max() ?? -1) + 1
        phase.goal = goal
        context.insert(phase)
        if goal.type == .numeric {
            goal.allowsPlan = true
        }
        goal.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .roadmapEdited,
            summary: "Added phase \(trimmed)",
            after: trimmed
        )
        try StoreSaving.save(context)
        return phase
    }

    func renamePhase(_ phase: Phase, title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalid("Add a phase title.") }
        let before = phase.title
        guard before != trimmed else { return }
        phase.title = trimmed
        phase.updatedAt = .now
        phase.goal?.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: phase.goal,
            type: .roadmapEdited,
            summary: "Renamed phase to \(trimmed)",
            before: before,
            after: trimmed
        )
        try StoreSaving.save(context)
    }

    func softDeletePhase(_ phase: Phase) {
        let now = Date()
        phase.deletedAt = now
        phase.updatedAt = now
        for checkpoint in phase.checkpoints ?? [] where checkpoint.deletedAt == nil {
            markCheckpointDeleted(checkpoint, at: now)
        }
        for resource in phase.resources ?? [] where resource.deletedAt == nil {
            resource.deletedAt = now
        }
        phase.goal?.updatedAt = now
        ActivityLog.record(
            in: context,
            goal: phase.goal,
            type: .roadmapEdited,
            summary: "Removed phase \(phase.title)",
            detail: phase.title
        )
        try? StoreSaving.save(context)
    }

    func movePhases(in goal: Goal, from offsets: IndexSet, to offset: Int) {
        var phases = goal.sortedPhases
        phases.move(fromOffsets: offsets, toOffset: offset)
        for (index, phase) in phases.enumerated() {
            phase.sortIndex = index
            phase.updatedAt = .now
        }
        goal.updatedAt = .now
        ActivityLog.record(in: context, goal: goal, type: .roadmapEdited, summary: "Reordered phases")
        try? StoreSaving.save(context)
    }

    @discardableResult
    func addCheckpoint(to phase: Phase, title: String, targetDate: Date? = nil) throws -> Checkpoint {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalid("Add a checkpoint title.") }
        let checkpoint = Checkpoint()
        checkpoint.title = trimmed
        checkpoint.targetDate = targetDate
        checkpoint.sortIndex = (phase.sortedCheckpoints.map(\.sortIndex).max() ?? -1) + 1
        checkpoint.phase = phase
        context.insert(checkpoint)
        phase.updatedAt = .now
        phase.goal?.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: phase.goal,
            type: .roadmapEdited,
            summary: "Added checkpoint \(trimmed)",
            after: trimmed
        )
        try StoreSaving.save(context)
        return checkpoint
    }

    func renameCheckpoint(_ checkpoint: Checkpoint, title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalid("Add a checkpoint title.") }
        let before = checkpoint.title
        guard before != trimmed else { return }
        checkpoint.title = trimmed
        checkpoint.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: checkpoint.phase?.goal,
            type: .roadmapEdited,
            summary: "Renamed checkpoint to \(trimmed)",
            before: before,
            after: trimmed
        )
        try StoreSaving.save(context)
    }

    func setCheckpointTarget(_ checkpoint: Checkpoint, date: Date?) {
        checkpoint.targetDate = date
        checkpoint.updatedAt = .now
        checkpoint.phase?.goal?.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: checkpoint.phase?.goal,
            type: .roadmapEdited,
            summary: "Updated the date for \(checkpoint.title)",
            after: date?.formatted(date: .abbreviated, time: .omitted) ?? "No date"
        )
        try? StoreSaving.save(context)
    }

    func setCheckpointNotes(_ checkpoint: Checkpoint, notes: String) {
        checkpoint.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        checkpoint.updatedAt = .now
        try? StoreSaving.save(context)
    }

    /// Returns true when the checkpoint is now complete.
    @discardableResult
    func toggleCheckpoint(_ checkpoint: Checkpoint) -> Bool {
        let goal = checkpoint.phase?.goal
        let now = Date()
        if checkpoint.completedAt == nil {
            checkpoint.completedAt = now
            checkpoint.updatedAt = now
            ActivityLog.record(
                in: context,
                goal: goal,
                type: .checkpointCompleted,
                summary: ActivitySummary.checkpointCompleted(checkpoint.title),
                detail: checkpoint.title
            )
            if let goal {
                GoalRepository(context: context).noteProgressStarted(goal)
            }
            try? StoreSaving.save(context)
            return true
        } else {
            checkpoint.completedAt = nil
            checkpoint.updatedAt = now
            ActivityLog.record(
                in: context,
                goal: goal,
                type: .checkpointReopened,
                summary: ActivitySummary.checkpointReopened(checkpoint.title),
                detail: checkpoint.title
            )
            if let goal, goal.status == .completed {
                GoalRepository(context: context).setStatus(goal, to: .inProgress)
            }
            try? StoreSaving.save(context)
            return false
        }
    }

    func softDeleteCheckpoint(_ checkpoint: Checkpoint) {
        let now = Date()
        markCheckpointDeleted(checkpoint, at: now)
        checkpoint.phase?.updatedAt = now
        checkpoint.phase?.goal?.updatedAt = now
        ActivityLog.record(
            in: context,
            goal: checkpoint.phase?.goal,
            type: .roadmapEdited,
            summary: "Removed checkpoint \(checkpoint.title)",
            detail: checkpoint.title
        )
        try? StoreSaving.save(context)
    }

    func moveCheckpoints(in phase: Phase, from offsets: IndexSet, to offset: Int) {
        var rows = phase.sortedCheckpoints
        rows.move(fromOffsets: offsets, toOffset: offset)
        for (index, checkpoint) in rows.enumerated() {
            checkpoint.sortIndex = index
            checkpoint.updatedAt = .now
        }
        phase.updatedAt = .now
        phase.goal?.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: phase.goal,
            type: .roadmapEdited,
            summary: "Reordered checkpoints in \(phase.title)"
        )
        try? StoreSaving.save(context)
    }

    @discardableResult
    func addResource(
        title: String,
        url rawURL: String,
        note: String,
        phase: Phase?,
        checkpoint: Checkpoint?
    ) throws -> ResourceLink {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalid("Add a title.") }
        guard let url = LinkURL.normalize(rawURL) else {
            throw RepositoryError.invalid("Enter a web address.")
        }
        let resource = ResourceLink()
        resource.title = trimmed
        resource.urlString = url
        resource.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        resource.phase = phase
        resource.checkpoint = checkpoint
        context.insert(resource)
        let goal = phase?.goal ?? checkpoint?.phase?.goal
        goal?.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .roadmapEdited,
            summary: "Added resource \(trimmed)",
            after: url
        )
        try StoreSaving.save(context)
        return resource
    }

    func importRoadmap(_ draft: RoadmapDraft, into goal: Goal, mode: PlanImportMode) throws {
        switch goal.type {
        case .habit:
            throw RepositoryError.invalid("Habits don't use a roadmap.")
        case .oneTime:
            throw RepositoryError.invalid("One-time tasks don't use a roadmap.")
        case .milestone, .project, .numeric:
            break
        }
        let phases = draft.phases.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !phases.isEmpty else { throw RepositoryError.invalid("Add a phase title.") }

        let now = Date()
        if mode == .replace {
            for phase in goal.phases ?? [] where phase.deletedAt == nil {
                phase.deletedAt = now
                phase.updatedAt = now
                for checkpoint in phase.checkpoints ?? [] where checkpoint.deletedAt == nil {
                    markCheckpointDeleted(checkpoint, at: now)
                }
                for resource in phase.resources ?? [] where resource.deletedAt == nil {
                    resource.deletedAt = now
                }
            }
        }

        var sortIndex = mode == .append ? (goal.sortedPhases.map(\.sortIndex).max() ?? -1) + 1 : 0
        for phaseDraft in phases {
            let phase = Phase()
            phase.title = phaseDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            phase.notes = phaseDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            phase.sortIndex = sortIndex
            phase.goal = goal
            context.insert(phase)
            sortIndex += 1
            addImportedLinks(phaseDraft.links, phase: phase, checkpoint: nil)

            var checkpointIndex = 0
            for checkpointDraft in phaseDraft.checkpoints {
                let title = checkpointDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let checkpoint = Checkpoint()
                checkpoint.title = title
                checkpoint.notes = checkpointDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                checkpoint.sortIndex = checkpointIndex
                checkpoint.phase = phase
                context.insert(checkpoint)
                checkpointIndex += 1
                addImportedLinks(checkpointDraft.links, phase: nil, checkpoint: checkpoint)
            }
        }

        if goal.type == .numeric {
            goal.allowsPlan = true
        }
        goal.updatedAt = now
        let checkpointCount = phases.reduce(0) { $0 + $1.checkpoints.count }
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .roadmapEdited,
            summary: "Imported a plan",
            detail: "\(phases.count) phases, \(checkpointCount) checkpoints"
        )
        try StoreSaving.save(context)
    }

    func softDeleteResource(_ resource: ResourceLink) {
        resource.deletedAt = .now
        let goal = resource.phase?.goal ?? resource.checkpoint?.phase?.goal
        goal?.updatedAt = .now
        ActivityLog.record(
            in: context,
            goal: goal,
            type: .roadmapEdited,
            summary: "Removed resource \(resource.title)",
            detail: resource.title
        )
        try? StoreSaving.save(context)
    }

    private func addImportedLinks(_ links: [RoadmapLinkDraft], phase: Phase?, checkpoint: Checkpoint?) {
        for link in links {
            guard let url = LinkURL.normalize(link.url) else { continue }
            let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let resource = ResourceLink()
            resource.title = title
            resource.urlString = url
            resource.phase = phase
            resource.checkpoint = checkpoint
            context.insert(resource)
        }
    }

    private func markCheckpointDeleted(_ checkpoint: Checkpoint, at now: Date) {
        checkpoint.deletedAt = now
        checkpoint.updatedAt = now
        for resource in checkpoint.resources ?? [] where resource.deletedAt == nil {
            resource.deletedAt = now
        }
    }
}
