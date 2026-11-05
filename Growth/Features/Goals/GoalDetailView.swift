import SwiftUI
import SwiftData

enum GoalDetailSection: String, CaseIterable, Identifiable {
    case overview
    case plan
    case activity
    case reflections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .plan: "Plan"
        case .activity: "Activity"
        case .reflections: "Reflect"
        }
    }
}

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var goal: Goal

    @State private var section: GoalDetailSection = .overview
    @State private var showEditor = false
    @State private var showValueUpdate = false
    @State private var showHabitLog = false
    @State private var showReminder = false
    @State private var showReflection = false
    @State private var showRecalibrate = false
    @State private var pendingCompletion = false
    @State private var errorMessage: String?
    @State private var reminderCheckpoint: Checkpoint?

    private var sections: [GoalDetailSection] {
        GoalDetailSection.allCases.filter { section in
            section != .plan || goal.showsPlan
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Section", selection: $section) {
                    ForEach(sections) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            switch section {
            case .overview:
                overview
            case .plan:
                PlanSection(goal: goal, onProgress: considerCompletion)
            case .activity:
                ActivityTimeline(goal: goal)
            case .reflections:
                ReflectionSection(goal: goal, onRecalibrate: { showRecalibrate = true })
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit details", systemImage: "pencil") { showEditor = true }
                    Menu("Status", systemImage: "circle.lefthalf.filled") {
                        ForEach(GoalStatus.allCases) { status in
                            Button(status.title) {
                                GoalRepository(context: context).setStatus(goal, to: status)
                                Task { await NotificationScheduler.reschedule(context: context) }
                            }
                        }
                    }
                    Button("Add reminder", systemImage: "bell") { showReminder = true }
                    Button("Recalibrate", systemImage: "arrow.triangle.branch") { showRecalibrate = true }
                    Divider()
                    Button("Delete goal", systemImage: "trash", role: .destructive) {
                        deleteGoal()
                    }
                    .accessibilityIdentifier("goal.delete")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("goal.menu")
            }
            if section == .plan {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack { GoalEditorView(goal: goal) }
        }
        .sheet(isPresented: $showValueUpdate) {
            NavigationStack { NumericUpdateView(goal: goal, onSaved: considerCompletion) }
        }
        .sheet(isPresented: $showHabitLog) {
            NavigationStack { HabitLogView(goal: goal, onSaved: considerCompletion) }
        }
        .sheet(isPresented: $showReminder) {
            NavigationStack { ReminderEditorView(goal: goal, checkpoint: reminderCheckpoint, existing: nil) }
        }
        .sheet(isPresented: $showReflection) {
            NavigationStack { ReflectionEditorView(goal: goal, presetFeeling: nil) }
        }
        .sheet(isPresented: $showRecalibrate) {
            NavigationStack { RecalibrateFlowView(goal: goal) }
        }
        .alert("Mark complete?", isPresented: $pendingCompletion) {
            Button("Not now", role: .cancel) {}
            Button("Mark complete") {
                GoalRepository(context: context).setStatus(goal, to: .completed)
                Task { await NotificationScheduler.reschedule(context: context) }
            }
        } message: {
            Text(goal.type == .numeric ? "You've reached the target." : "Every checkpoint is done.")
        }
        .alert("Couldn't update", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: goal.showsPlan) { _, shows in
            if !shows, section == .plan { section = .overview }
        }
    }

    private func deleteGoal() {
        GoalRepository(context: context).softDelete(goal)
        Task { await NotificationScheduler.reschedule(context: context) }
        dismiss()
    }

    @ViewBuilder
    private var overview: some View {
        let presentation = goal.progressPresentation()
        Section {
            StatusBadge(status: goal.status)
            if !goal.category.isEmpty {
                LabeledContent("Category", value: goal.category)
            }
            if !goal.details.isEmpty {
                Text(goal.details)
            }
            if !goal.notes.isEmpty {
                Text(goal.notes)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Started", value: goal.startDate.formatted(date: .abbreviated, time: .omitted))
            if let targetDate = goal.targetDate {
                DueDateText(date: targetDate)
            }
        }

        Section("Progress") {
            ProgressMeter(fraction: presentation.fraction, caption: presentation.caption)
            if let note = presentation.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            primaryAction
        }

        if goal.isPastDue() {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A date on this goal is past due. You can leave the plan as it is, or recalibrate.")
                        .font(.subheadline)
                    Button("Recalibrate") { showRecalibrate = true }
                }
            }
        }

        if goal.type == .numeric && !goal.allowsPlan {
            Section {
                Button("Add milestones") {
                    GoalRepository(context: context).enablePlan(goal)
                    section = .plan
                }
                Text("Optional checkpoints sit beside the number. They don't change the percentage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        if goal.type == .milestone || goal.type == .project, let next = goal.allCheckpoints.first(where: { $0.completedAt == nil }) {
            Section("Next") {
                Text(next.title)
                if let date = next.targetDate {
                    DueDateText(date: date)
                }
            }
        }

        if goal.type == .numeric {
            Section("History") {
                let history = ProgressRepository(context: context).history(goal)
                if history.isEmpty {
                    Text("Each update is kept. Nothing is overwritten.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DecimalText.string(entry.value))
                                .font(.body.monospacedDigit())
                            Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
        }

        if goal.type == .habit {
            HabitOverview(goal: goal)
        }

        Section("Reminders") {
                ForEach(goal.activeReminders) { reminder in
                    NavigationLink {
                        ReminderEditorView(goal: goal, checkpoint: reminder.checkpoint, existing: reminder)
                    } label: {
                        ReminderRow(reminder: reminder)
                    }
                }
                Button("Add reminder") {
                    reminderCheckpoint = nil
                    showReminder = true
                }
        }

        if !goal.linkedJournal.isEmpty {
            Section("Journal") {
                ForEach(goal.linkedJournal) { entry in
                    NavigationLink {
                        JournalEditorView(entry: entry)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.title).font(.body)
                            Text(entry.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch goal.type {
        case .milestone, .project:
            Button(goal.allCheckpoints.isEmpty ? "Add a phase" : "Continue plan") {
                section = .plan
            }
            .accessibilityIdentifier("overview.continuePlan")
        case .numeric:
            Button("Update value") { showValueUpdate = true }
                .accessibilityIdentifier("overview.updateValue")
        case .habit:
            Button("Log habit") { showHabitLog = true }
                .accessibilityIdentifier("overview.logHabit")
        case .oneTime:
            if goal.status == .completed {
                Button("Reopen") {
                    GoalRepository(context: context).setStatus(goal, to: .inProgress)
                    Task { await NotificationScheduler.reschedule(context: context) }
                }
                .accessibilityIdentifier("overview.reopenTask")
            } else {
                Button("Mark done") {
                    GoalRepository(context: context).setStatus(goal, to: .completed)
                    Task { await NotificationScheduler.reschedule(context: context) }
                }
                .accessibilityIdentifier("overview.markDone")
            }
        }
    }

    private func considerCompletion() {
        if goal.canPromptCompletion && goal.suggestsCompletion {
            pendingCompletion = true
        }
    }
}

struct HabitOverview: View {
    var goal: Goal

    private var calendar: Calendar { .current }

    var body: some View {
        let marks = HabitPeriod.weekMarks(
            schedule: goal.habitSchedule,
            logDates: goal.activeHabitLogs.map(\.occurredOn),
            now: .now,
            calendar: calendar
        )
        let previous = HabitPeriod.previous(
            schedule: goal.habitSchedule,
            logDates: goal.activeHabitLogs.map(\.occurredOn),
            now: .now,
            calendar: calendar
        )
        Section("This week") {
            HStack {
                ForEach(marks) { mark in
                    VStack(spacing: 4) {
                        Text(mark.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(fill(for: mark.state))
                            .frame(width: 14, height: 14)
                            .overlay {
                                if mark.state == .open {
                                    Circle().stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(mark.state == .off ? 0.25 : 1)
                }
            }
            .padding(.vertical, 4)
        }
        if !previous.isEmpty {
            Section("Earlier weeks") {
                ForEach(Array(previous.enumerated()), id: \.offset) { index, snapshot in
                    LabeledContent(weekLabel(index)) {
                        Text("\(snapshot.completed) of \(snapshot.expected)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func fill(for state: HabitDayMark.State) -> Color {
        switch state {
        case .logged: Color.accentColor
        case .open: Color.clear
        case .later: Color.secondary.opacity(0.18)
        case .off: Color.secondary.opacity(0.12)
        }
    }

    private func weekLabel(_ index: Int) -> String {
        switch index {
        case 0: "Last week"
        case 1: "2 weeks ago"
        default: "3 weeks ago"
        }
    }
}

struct NumericUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var goal: Goal
    var onSaved: () -> Void

    @State private var valueText = ""
    @State private var recordedAt = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Value", text: $valueText)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("progress.value")
                DatePicker("When", selection: $recordedAt)
                TextField("Note", text: $note, axis: .vertical)
            } footer: {
                Text("This adds a new row. Earlier values stay as they were.")
            }
        }
        .navigationTitle("Update value")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .accessibilityIdentifier("progress.save")
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        guard let value = NumberParsing.double(from: valueText) else {
            errorMessage = "Enter a number."
            return
        }
        do {
            try ProgressRepository(context: context).addEntry(
                goal: goal,
                value: value,
                recordedAt: recordedAt,
                note: note
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct HabitLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var goal: Goal
    var onSaved: () -> Void

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
            TextField("Note", text: $note, axis: .vertical)
        }
        .navigationTitle("Log habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") { save() }
                    .accessibilityIdentifier("habit.save")
            }
        }
        .alert("Couldn't log", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            try HabitRepository(context: context).log(goal: goal, on: day, note: note)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
