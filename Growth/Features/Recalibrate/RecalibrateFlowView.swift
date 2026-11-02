import SwiftUI
import SwiftData

struct RecalibrateFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var goal: Goal

    @State private var step = 0
    @State private var situation = ""
    @State private var reflectionNote = ""
    @State private var startedAt = Date()
    @State private var hasTargetDate = false
    @State private var targetDate = Date()
    @State private var startDate = Date()
    @State private var numericTargetText = ""
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: 4)
                .padding(.horizontal)
                .padding(.top, 8)
            Group {
                switch step {
                case 0: situationStep
                case 1: reflectionStep
                case 2: adjustStep
                default: continueStep
                }
            }
        }
        .navigationTitle("Recalibrate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            startedAt = Date()
            startDate = goal.startDate
            hasTargetDate = goal.targetDate != nil
            targetDate = goal.targetDate ?? .now
            numericTargetText = goal.numericTarget.map(DecimalText.string) ?? ""
        }
    }

    private var situationStep: some View {
        Form {
            Section {
                TextField("What's going on?", text: $situation, axis: .vertical)
                    .lineLimit(4...10)
            } footer: {
                Text("This is the reason the plan is changing. It's saved with the recalibration.")
            }
            Section {
                Button("Continue") { step = 1 }
                    .disabled(situation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var reflectionStep: some View {
        Form {
            Section {
                TextField("What do you want from here?", text: $reflectionNote, axis: .vertical)
                    .lineLimit(4...10)
            } footer: {
                Text("Optional. A fuller reflection can still be written on the goal later.")
            }
            Section {
                Button("Continue") { step = 2 }
                Button("Skip") { step = 2 }
            }
        }
    }

    private var adjustStep: some View {
        List {
            Section("Dates") {
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                Toggle("Target date", isOn: $hasTargetDate)
                if hasTargetDate {
                    DatePicker("Target", selection: $targetDate, displayedComponents: .date)
                }
            }
            if goal.type == .numeric {
                Section("Target value") {
                    TextField("Target", text: $numericTargetText)
                        .keyboardType(.numbersAndPunctuation)
                    Text("Earlier value updates stay in the history.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if goal.showsPlan {
                PlanSection(goal: goal, onProgress: {})
            } else if goal.type == .numeric {
                Section {
                    Button("Add milestones") {
                        GoalRepository(context: context).enablePlan(goal)
                    }
                }
            }
            Section("Reminders") {
                ForEach(goal.activeReminders) { reminder in
                    NavigationLink {
                        ReminderEditorView(goal: goal, checkpoint: reminder.checkpoint, existing: reminder)
                    } label: {
                        ReminderRow(reminder: reminder)
                    }
                }
                NavigationLink("Add reminder") {
                    ReminderEditorView(goal: goal, checkpoint: nil, existing: nil)
                }
            }
            Section {
                Button("Continue") {
                    saveAdjustments()
                    step = 3
                }
            } footer: {
                Text("Changes you make here are kept either way. Finishing writes the recalibration on top of that history.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var continueStep: some View {
        Form {
            Section("Situation") {
                Text(situation)
            }
            if !reflectionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("From here") {
                    Text(reflectionNote)
                }
            }
            Section {
                Text("Nothing already logged is discarded. The activity timeline keeps the before and after.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Finish") { finish() }
                    .accessibilityIdentifier("recalibrate.finish")
            }
        }
    }

    private func saveAdjustments() {
        var draft = GoalDraft(goal: goal)
        draft.startDate = startDate
        draft.hasTargetDate = hasTargetDate
        draft.targetDate = targetDate
        if goal.type == .numeric, let value = NumberParsing.double(from: numericTargetText) {
            draft.numericTarget = value
        }
        try? GoalRepository(context: context).update(goal, draft: draft)
    }

    private func finish() {
        _ = RecalibrationRepository(context: context).finish(
            goal: goal,
            situation: situation,
            reflectionNote: reflectionNote,
            startedAt: startedAt
        )
        dismiss()
    }
}
