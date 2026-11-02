import SwiftUI
import SwiftData

struct CheckInScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(NotificationPermission.self) private var permissions

    @State private var weekday = 2
    @State private var time = Date()
    @State private var enabled = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Picker("Weekday", selection: $weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Toggle("Enabled", isOn: $enabled)
            } footer: {
                if permissions.isDenied {
                    Text("Notifications are off. The check-in still shows on Home that weekday. Open Settings if you also want the alert.")
                } else {
                    Text("One card per active goal. You can skip any of them.")
                }
            }
            if permissions.isDenied {
                Section {
                    Button("Open Settings") { SystemSettings.open() }
                }
            }
        }
        .navigationTitle("Weekly check-in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear {
            guard !loaded else { return }
            let schedule = CheckInRepository(context: context).schedule()
            weekday = schedule.weekday
            enabled = schedule.enabled
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            parts.hour = schedule.hour
            parts.minute = schedule.minute
            time = Calendar.current.date(from: parts) ?? .now
            loaded = true
        }
    }

    private func save() {
        Task { await saveAsync() }
    }

    private func saveAsync() async {
        if enabled, permissions.status == .notDetermined {
            _ = await permissions.request()
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let repository = CheckInRepository(context: context)
        let schedule = repository.schedule()
        try? repository.updateSchedule(
            schedule,
            weekday: weekday,
            hour: parts.hour ?? 9,
            minute: parts.minute ?? 0,
            enabled: enabled
        )
        await NotificationScheduler.reschedule(context: context)
        dismiss()
    }
}

struct CheckInFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var goals: [Goal]

    @State private var items: [CheckInDraftItem] = []
    @State private var index = 0
    @State private var finished = false
    @State private var reflectionGoal: Goal?
    @State private var recalibrateGoal: Goal?

    var body: some View {
        Group {
            if goals.isEmpty {
                ContentUnavailableView(
                    "No active goals",
                    systemImage: "checkmark.circle",
                    description: Text("The check-in looks at goals that are not paused, complete, or archived.")
                )
            } else if finished {
                closer
            } else if items.indices.contains(index) {
                card
            }
        }
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            if items.isEmpty {
                items = goals.map {
                    CheckInDraftItem(id: UUID(), goalID: $0.id, goalTitle: $0.title)
                }
            }
        }
        .sheet(item: $reflectionGoal) { goal in
            NavigationStack {
                ReflectionEditorView(goal: goal, presetFeeling: feeling(for: goal))
            }
        }
        .sheet(item: $recalibrateGoal) { goal in
            NavigationStack { RecalibrateFlowView(goal: goal) }
        }
    }

    private var card: some View {
        let binding = $items[index]
        return Form {
            Section {
                Text(binding.wrappedValue.goalTitle)
                    .font(.title3.weight(.semibold))
                Text("\(index + 1) of \(items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !binding.wrappedValue.skipped {
                Section("Feeling") {
                    ForEach(Feeling.allCases) { feeling in
                        Button {
                            binding.wrappedValue.feeling = feeling
                        } label: {
                            HStack {
                                Label(feeling.title, systemImage: feeling.symbolName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if binding.wrappedValue.feeling == feeling {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("What happened?", text: binding.whatHappened, axis: .vertical)
                    TextField("What will you change?", text: binding.whatWillChange, axis: .vertical)
                }
            } else {
                Section {
                    Text("Skipped. It won't be part of the closer.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button(binding.wrappedValue.skipped ? "Include this goal" : "Skip this goal") {
                    binding.wrappedValue.skipped.toggle()
                    if binding.wrappedValue.skipped {
                        binding.wrappedValue.feeling = nil
                    }
                }
                Button(index == items.count - 1 ? "Finish" : "Next") {
                    advance()
                }
                .disabled(!binding.wrappedValue.skipped && binding.wrappedValue.feeling == nil)
                .accessibilityIdentifier("checkIn.next")
            }
        }
    }

    private var closer: some View {
        let flagged = items.filter { !$0.skipped && $0.feeling?.wantsDeeperLook == true }
        return List {
            Section {
                Text("That's the pass. Nothing here changes the plan unless you choose to recalibrate.")
                    .foregroundStyle(.secondary)
            }
            if flagged.isEmpty {
                Section {
                    Text("No goals marked behind or stuck.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("If you want to go further") {
                    ForEach(flagged) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.goalTitle).font(.headline)
                            Text(item.feeling?.title ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let goal = goals.first(where: { $0.id == item.goalID }) {
                                Button("Write a reflection") { reflectionGoal = goal }
                                Button("Recalibrate") { recalibrateGoal = goal }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("checkIn.done")
            }
        }
    }

    private func advance() {
        if index == items.count - 1 {
            CheckInRepository(context: context).saveSession(items, goals: goals)
            finished = true
        } else {
            index += 1
        }
    }

    private func feeling(for goal: Goal) -> Feeling? {
        items.first { $0.goalID == goal.id }?.feeling
    }
}
