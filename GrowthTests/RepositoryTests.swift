import XCTest
import SwiftData
@testable import Growth

@MainActor
final class RepositoryTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = ModelContainerFactory.make(inMemory: true)
    }

    private var context: ModelContext { container.mainContext }

    func testCreateLogsActivityAndRejectsEmptyTitle() throws {
        let repository = GoalRepository(context: context)
        XCTAssertThrowsError(try repository.create(GoalDraft()))
        var draft = GoalDraft()
        draft.title = "Neural networks"
        draft.type = .milestone
        draft.category = "Learning"
        let goal = try repository.create(draft)
        let events = events(for: goal)
        XCTAssertEqual(events.map(\.type), [.created])
        XCTAssertEqual(GoalRepository.filtered(repository.allGoals(), status: nil, search: "learn").map(\.id), [goal.id])
        XCTAssertTrue(GoalRepository.active([goal]).contains(where: { $0.id == goal.id }))
    }

    func testCheckpointCompletionStartsTheGoalAndKeepsHistoryWhenRemoved() throws {
        var draft = GoalDraft()
        draft.title = "Ship the essay"
        draft.type = .project
        let goal = try GoalRepository(context: context).create(draft)
        let phase = try PlanRepository(context: context).addPhase(to: goal, title: "Draft")
        let checkpoint = try PlanRepository(context: context).addCheckpoint(to: phase, title: "Outline")
        XCTAssertTrue(PlanRepository(context: context).toggleCheckpoint(checkpoint))
        XCTAssertEqual(goal.status, .inProgress)
        XCTAssertEqual(goal.suggestsCompletion, true)
        XCTAssertEqual(goal.progressPresentation().fraction, 1)

        PlanRepository(context: context).softDeleteCheckpoint(checkpoint)
        XCTAssertTrue(goal.allCheckpoints.isEmpty)
        XCTAssertFalse(goal.suggestsCompletion)
        XCTAssertTrue(events(for: goal).contains(where: { $0.type == .checkpointCompleted && $0.summary.contains("Outline") }))
        XCTAssertTrue(events(for: goal).contains(where: { $0.summary.contains("Removed checkpoint Outline") }))
    }

    func testReorderRewritesSortIndex() throws {
        var draft = GoalDraft()
        draft.title = "Course"
        draft.type = .milestone
        let goal = try GoalRepository(context: context).create(draft)
        let plan = PlanRepository(context: context)
        let first = try plan.addPhase(to: goal, title: "A")
        _ = try plan.addPhase(to: goal, title: "B")
        _ = try plan.addPhase(to: goal, title: "C")
        plan.movePhases(in: goal, from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(goal.sortedPhases.map(\.title), ["B", "C", "A"])
        XCTAssertEqual(goal.sortedPhases.map(\.sortIndex), [0, 1, 2])
        XCTAssertEqual(first.title, "A")
    }

    func testNumericHistoryKeepsTheLatestDatedValue() throws {
        var draft = GoalDraft()
        draft.title = "Savings"
        draft.type = .numeric
        draft.numericStart = 0
        draft.numericTarget = 100
        draft.numericDirection = .increase
        draft.numericUnit = "dollars"
        let goal = try GoalRepository(context: context).create(draft)
        let progress = ProgressRepository(context: context)
        try progress.addEntry(goal: goal, value: 10, recordedAt: date(2026, 1, 2), note: "")
        try progress.addEntry(goal: goal, value: 5, recordedAt: date(2026, 1, 1), note: "backdated")
        XCTAssertEqual(goal.resolvedCurrent, 10)
        XCTAssertEqual(goal.status, .inProgress)
        XCTAssertEqual(progress.history(goal).map(\.value), [10, 5])
        XCTAssertFalse(goal.suggestsCompletion)
        try progress.addEntry(goal: goal, value: 100, recordedAt: date(2026, 1, 3), note: "")
        XCTAssertTrue(goal.suggestsCompletion)
        XCTAssertEqual(goal.progressPresentation().fraction ?? -1, 1, accuracy: 0.0001)
    }

    func testDecreaseGoalDoesNotTreatTheStartAsComplete() throws {
        var draft = GoalDraft()
        draft.title = "Weight"
        draft.type = .numeric
        draft.numericDirection = .decrease
        draft.numericStart = 80
        draft.numericTarget = 75
        let goal = try GoalRepository(context: context).create(draft)
        XCTAssertEqual(goal.progressPresentation().fraction, 0)
        XCTAssertFalse(goal.suggestsCompletion)
    }

    func testHabitLogIsOnePerDayAndQuotaLimited() throws {
        var draft = GoalDraft()
        draft.title = "Walk"
        draft.type = .habit
        draft.habitFrequency = .weeklyQuota
        draft.weeklyQuota = 1
        let goal = try GoalRepository(context: context).create(draft)
        let habits = HabitRepository(context: context)
        try habits.log(goal: goal, on: Date(), note: "")
        XCTAssertEqual(goal.status, .inProgress)
        XCTAssertThrowsError(try habits.log(goal: goal, on: Date(), note: "again"))
        XCTAssertThrowsError(try PlanRepository(context: context).addPhase(to: goal, title: "Nope"))
        XCTAssertFalse(goal.showsPlan)
    }

    func testPauseArchiveAndDeleteKeepHistory() throws {
        var draft = GoalDraft()
        draft.title = "Essay"
        draft.type = .milestone
        let goal = try GoalRepository(context: context).create(draft)
        let goals = GoalRepository(context: context)
        goals.setStatus(goal, to: .paused)
        XCTAssertTrue(goal.silencesReminders)
        XCTAssertFalse(GoalRepository.active([goal]).contains(where: { $0.id == goal.id }))
        goals.setStatus(goal, to: .inProgress)
        XCTAssertEqual(events(for: goal).last?.type, .resumed)
        goals.setStatus(goal, to: .archived)
        XCTAssertTrue(goal.silencesReminders)

        let entry = try JournalRepository(context: context).save(existing: nil, title: "Note", body: "Kept", goals: [goal])
        _ = ReflectionRepository(context: context).create(
            goal: goal,
            feeling: .stuck,
            expected: "",
            happened: "Stalled",
            worked: "",
            inTheWay: "",
            learned: "",
            nextChange: ""
        )
        goals.softDelete(goal)
        XCTAssertNotNil(goal.deletedAt)
        XCTAssertTrue((entry.goals ?? []).isEmpty)
        XCTAssertFalse(entry.body.isEmpty)
        XCTAssertEqual(entry.deletedAt, nil)
        XCTAssertFalse((goal.reflections ?? []).isEmpty)
        XCTAssertTrue(events(for: goal).contains(where: { $0.type == .deleted }))
        XCTAssertTrue(events(for: goal).contains(where: { $0.goalTitle == "Essay" }))
    }

    func testRecalibrationReferencesEventsWithoutErasingThem() throws {
        var draft = GoalDraft()
        draft.title = "Move"
        draft.type = .milestone
        draft.hasTargetDate = true
        draft.targetDate = date(2026, 1, 1)
        let goal = try GoalRepository(context: context).create(draft)
        let started = Date()
        var updated = GoalDraft(goal: goal)
        updated.targetDate = date(2026, 6, 1)
        try GoalRepository(context: context).update(goal, draft: updated)
        let record = RecalibrationRepository(context: context).finish(
            goal: goal,
            situation: "The date slipped",
            reflectionNote: "Keep the same shape",
            startedAt: started
        )
        XCTAssertTrue(record.eventIDs.count >= 2)
        XCTAssertEqual(record.situation, "The date slipped")
        XCTAssertTrue(events(for: goal).contains(where: { $0.type == .recalibrated }))
        XCTAssertTrue(events(for: goal).contains(where: { $0.type == .roadmapEdited }))
    }

    private func events(for goal: Goal) -> [ActivityEvent] {
        (goal.activityEvents ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts)!
    }
}
