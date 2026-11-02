import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.updatedAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \CheckInSchedule.createdAt) private var schedules: [CheckInSchedule]
    @Query(sort: \CheckInSession.createdAt, order: .reverse) private var sessions: [CheckInSession]
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]

    @State private var showGoalEditor = false
    @State private var showJournalEditor = false
    @State private var showCheckIn = false
    @State private var showSchedule = false
    @State private var showReminders = false
    @State private var path: [UUID] = []

    private var activeGoals: [Goal] {
        GoalRepository.homeSorted(goals)
    }

    private var schedule: CheckInSchedule? {
        schedules.first
    }

    private var checkInIsDue: Bool {
        guard let schedule else { return false }
        let hasSession = sessions.contains { Calendar.current.isDateInToday($0.createdAt) }
        return CheckInDue.isDue(
            enabled: schedule.enabled,
            weekday: schedule.weekday,
            hasSessionOnDay: hasSession
        )
    }

    private var upcoming: [Reminder] {
        ReminderRepository(context: context).upcoming(limit: 3)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if activeGoals.isEmpty && upcoming.isEmpty && !checkInIsDue {
                    EmptyStateView(
                        systemImage: "leaf",
                        title: "Nothing in motion",
                        message: "Goals you're actively working on will show up here. Paused and archived goals stay out of the way.",
                        actionTitle: "New goal",
                        action: { showGoalEditor = true }
                    )
                } else {
                    List {
                        if checkInIsDue {
                            Section {
                                Button {
                                    showCheckIn = true
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("Weekly check-in", systemImage: "checkmark.circle")
                                            .font(.headline)
                                        Text("A short pass over \(activeGoals.count) active goal\(activeGoals.count == 1 ? "" : "s"). Skip any you don't want to touch.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityIdentifier("home.checkIn")
                            }
                        } else if schedule?.enabled != true {
                            Section {
                                Button {
                                    showSchedule = true
                                } label: {
                                    Label("Set a weekly check-in", systemImage: "calendar.badge.clock")
                                }
                            }
                        }

                        Section("Active") {
                            if activeGoals.isEmpty {
                                Text("No active goals. Paused, complete, and archived goals stay off this list.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(activeGoals) { goal in
                                    NavigationLink(value: goal.id) {
                                        GoalRow(goal: goal)
                                    }
                                }
                            }
                        }

                        Section("Reminders") {
                            if upcoming.isEmpty {
                                Text("Nothing coming up.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(upcoming) { reminder in
                                    ReminderRow(reminder: reminder)
                                }
                            }
                            Button("See all reminders") { showReminders = true }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showGoalEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("home.newGoal")
                    .accessibilityLabel("New goal")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showJournalEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityIdentifier("home.newJournal")
                    .accessibilityLabel("New journal entry")
                }
            }
            .sheet(isPresented: $showGoalEditor) {
                NavigationStack { GoalEditorView(goal: nil) }
            }
            .sheet(isPresented: $showJournalEditor) {
                NavigationStack { JournalEditorView(entry: nil) }
            }
            .sheet(isPresented: $showCheckIn) {
                NavigationStack {
                    CheckInFlowView(goals: activeGoals)
                }
            }
            .sheet(isPresented: $showSchedule) {
                NavigationStack { CheckInScheduleView() }
            }
            .navigationDestination(for: UUID.self) { id in
                if let goal = goals.first(where: { $0.id == id && $0.deletedAt == nil }) {
                    GoalDetailView(goal: goal)
                }
            }
            .navigationDestination(isPresented: $showReminders) {
                UpcomingRemindersView()
            }
            .onChange(of: deletedGoalIDs) { _, deleted in
                path.removeAll { deleted.contains($0) }
            }
        }
    }

    private var deletedGoalIDs: [UUID] {
        goals.compactMap { $0.deletedAt == nil ? nil : $0.id }
    }
}

struct GoalRow: View {
    var goal: Goal

    var body: some View {
        let presentation = goal.progressPresentation()
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .font(.headline)
                Spacer()
                StatusBadge(status: goal.status)
            }
            if !goal.category.isEmpty {
                Text(goal.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressMeter(fraction: presentation.fraction, caption: presentation.caption)
            if let note = presentation.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let targetDate = goal.targetDate {
                DueDateText(date: targetDate)
            }
        }
        .padding(.vertical, 4)
    }
}
