import SwiftUI
import SwiftData

struct GoalsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.updatedAt, order: .reverse) private var stored: [Goal]
    @State private var search = ""
    @State private var statusFilter: GoalStatus?
    @State private var showEditor = false
    @State private var path: [UUID] = []

    private var goals: [Goal] {
        GoalRepository.filtered(stored, status: statusFilter, search: search)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if stored.filter({ $0.deletedAt == nil }).isEmpty {
                    EmptyStateView(
                        systemImage: "flag",
                        title: "No goals yet",
                        message: "Start with a milestone, a project, a number, a habit, or a one-time task. You only fill in what that kind of goal needs.",
                        actionTitle: "New goal",
                        action: { showEditor = true }
                    )
                } else if goals.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List {
                        ForEach(goals) { goal in
                            NavigationLink(value: goal.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label(goal.type.title, systemImage: goal.type.symbolName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        StatusBadge(status: goal.status)
                                    }
                                    Text(goal.title)
                                        .font(.headline)
                                    if !goal.category.isEmpty {
                                        Text(goal.category)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressMeter(
                                        fraction: goal.progressPresentation().fraction,
                                        caption: goal.progressPresentation().caption
                                    )
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions {
                                Button("Archive", systemImage: "archivebox") {
                                    GoalRepository(context: context).setStatus(goal, to: .archived)
                                    Task { await NotificationScheduler.reschedule(context: context) }
                                }
                                .tint(.gray)
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    GoalRepository(context: context).softDelete(goal)
                                    Task { await NotificationScheduler.reschedule(context: context) }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Goals")
            .searchable(text: $search, prompt: "Title or category")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("goals.new")
                    .accessibilityLabel("New goal")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Status", selection: $statusFilter) {
                            Text("All").tag(Optional<GoalStatus>.none)
                            ForEach(GoalStatus.allCases) { status in
                                Text(status.title).tag(Optional(status))
                            }
                        }
                    } label: {
                        Label(statusFilter?.title ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("goals.filter")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let goal = stored.first(where: { $0.id == id && $0.deletedAt == nil }) {
                    GoalDetailView(goal: goal)
                }
            }
            .onChange(of: deletedGoalIDs) { _, deleted in
                path.removeAll { deleted.contains($0) }
            }
            .sheet(isPresented: $showEditor) {
                NavigationStack { GoalEditorView(goal: nil) }
            }
        }
    }

    private var deletedGoalIDs: [UUID] {
        stored.compactMap { $0.deletedAt == nil ? nil : $0.id }
    }
}

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let existing: Goal?
    @State private var draft: GoalDraft
    @State private var step: Step
    @State private var startText: String
    @State private var targetText: String
    @State private var errorMessage: String?

    enum Step {
        case type
        case form
    }

    init(goal: Goal?) {
        existing = goal
        if let goal {
            _draft = State(initialValue: GoalDraft(goal: goal))
            _step = State(initialValue: .form)
            _startText = State(initialValue: goal.numericStart.map(DecimalText.string) ?? "")
            _targetText = State(initialValue: goal.numericTarget.map(DecimalText.string) ?? "")
        } else {
            _draft = State(initialValue: GoalDraft())
            _step = State(initialValue: .type)
            _startText = State(initialValue: "")
            _targetText = State(initialValue: "")
        }
    }

    var body: some View {
        Group {
            switch step {
            case .type:
                typeChooser
            case .form:
                form
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

    private var typeChooser: some View {
        List(GoalType.allCases) { type in
            Button {
                draft.type = type
                if type == .oneTime {
                    draft.hasTargetDate = true
                    draft.targetDate = .now
                } else {
                    draft.hasTargetDate = false
                }
                step = .form
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: type.symbolName)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(type.blurb)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("goalType.\(type.rawValue)")
        }
        .navigationTitle("New goal")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Title", text: $draft.title)
                    .accessibilityIdentifier("goal.title")
                TextField("Category", text: $draft.category, prompt: Text("Health, learning, money"))
                    .accessibilityIdentifier("goal.category")
                TextField("Description", text: $draft.details, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
            Section("Dates") {
                DatePicker("Start", selection: $draft.startDate, displayedComponents: .date)
                Toggle("Target date", isOn: $draft.hasTargetDate)
                if draft.hasTargetDate {
                    DatePicker("Target", selection: $draft.targetDate, displayedComponents: .date)
                }
            }
            typeSection
            if let hint = GoalValidation.hint(for: draft) {
                Section {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(existing == nil ? "New \(draft.type.title.lowercased())" : "Edit goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if existing == nil, step == .form {
                    Button("Back") { step = .type }
                } else {
                    Button("Close") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(GoalValidation.message(for: draft) != nil)
                    .accessibilityIdentifier("goal.save")
            }
        }
        .onChange(of: startText) { _, newValue in
            draft.numericStart = NumberParsing.double(from: newValue)
        }
        .onChange(of: targetText) { _, newValue in
            draft.numericTarget = NumberParsing.double(from: newValue)
        }
    }

    @ViewBuilder
    private var typeSection: some View {
        switch draft.type {
        case .milestone, .project, .oneTime:
            Section {
                Text(draft.type.blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .numeric:
            Section("Number") {
                Picker("Direction", selection: $draft.numericDirection) {
                    ForEach(NumericDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                Text(draft.numericDirection.footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Start", text: $startText)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("goal.numericStart")
                TextField("Target", text: $targetText)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("goal.numericTarget")
                TextField("Unit", text: $draft.numericUnit, prompt: Text("kg, books, dollars"))
                    .accessibilityIdentifier("goal.numericUnit")
            }
        case .habit:
            Section("Habit") {
                Picker("Frequency", selection: $draft.habitFrequency) {
                    ForEach(HabitFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                if draft.habitFrequency == .weekdays {
                    WeekdayPicker(mask: $draft.weekdayMask)
                }
                if draft.habitFrequency == .weeklyQuota {
                    Stepper("\(draft.weeklyQuota) times per week", value: $draft.weeklyQuota, in: 1...7)
                        .accessibilityIdentifier("goal.habitQuota")
                }
                Text("One log per day. A missed day only changes this period's ratio.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        draft.numericStart = NumberParsing.double(from: startText)
        draft.numericTarget = NumberParsing.double(from: targetText)
        let repository = GoalRepository(context: context)
        do {
            if let existing {
                try repository.update(existing, draft: draft)
            } else {
                try repository.create(draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
