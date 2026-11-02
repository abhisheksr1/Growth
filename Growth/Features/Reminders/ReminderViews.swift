import SwiftUI
import SwiftData

struct ReminderRow: View {
    var reminder: Reminder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reminder.title)
                .font(.body)
            if !reminder.body.isEmpty {
                Text(reminder.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let snapshot = reminder.schedulingSnapshot, let next = ReminderScheduling.nextFireDate(snapshot) {
                Text(next.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if reminder.recurrence == .none {
                Text("No upcoming time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if reminder.goal?.silencesReminders == true {
                Text(reminder.goal?.status == .paused ? "Quiet while this goal is paused" : "Quiet while this goal is archived")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct UpcomingRemindersView: View {
    @Environment(\.modelContext) private var context
    @Environment(NotificationPermission.self) private var permissions
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]

    private var rows: [Reminder] {
        ReminderRepository(context: context).upcoming(limit: nil)
            + reminders.filter { reminder in
                guard reminder.deletedAt == nil else { return false }
                if reminder.goal?.silencesReminders == true { return true }
                return false
            }
    }

    var body: some View {
        Group {
            if rows.isEmpty && !permissions.isDenied {
                EmptyStateView(
                    systemImage: "bell",
                    title: "No reminders",
                    message: "Add one from a goal when you want a nudge. It can repeat daily, weekly, or monthly."
                )
            } else {
                List {
                    if permissions.isDenied {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notifications are off. Reminders you save stay here, and they'll be scheduled if you turn notifications on in Settings.")
                                    .font(.subheadline)
                                Button("Open Settings") { SystemSettings.open() }
                            }
                        }
                    } else if permissions.status == .notDetermined {
                        Section {
                            Text("You'll be asked before the first reminder is turned on. Saving a reminder doesn't require that yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        if rows.isEmpty {
                            Text("Nothing scheduled.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(unique(rows)) { reminder in
                                if let goal = reminder.goal {
                                    NavigationLink {
                                        ReminderEditorView(goal: goal, checkpoint: reminder.checkpoint, existing: reminder)
                                    } label: {
                                        ReminderRow(reminder: reminder)
                                    }
                                } else {
                                    NavigationLink {
                                        CheckInScheduleView()
                                    } label: {
                                        ReminderRow(reminder: reminder)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Reminders")
    }

    private func unique(_ reminders: [Reminder]) -> [Reminder] {
        var seen: Set<UUID> = []
        return reminders.filter { seen.insert($0.id).inserted }
    }
}

struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(NotificationPermission.self) private var permissions

    var goal: Goal?
    var checkpoint: Checkpoint?
    var existing: Reminder?

    @State private var title = ""
    @State private var bodyText = ""
    @State private var fireOn = Date()
    @State private var time = Date()
    @State private var weekday = 2
    @State private var recurrence: ReminderRecurrence = .none
    @State private var enabled = true
    @State private var errorMessage: String?
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                TextField("Body", text: $bodyText, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section {
                if recurrence != .daily {
                    DatePicker("Date", selection: $fireOn, displayedComponents: .date)
                }
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Picker("Repeat", selection: $recurrence) {
                    ForEach(ReminderRecurrence.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                if recurrence == .weekly {
                    Picker("Weekday", selection: $weekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                }
                Toggle("Enabled", isOn: $enabled)
            } footer: {
                if goal?.status == .paused {
                    Text("This goal is paused, so the reminder stays quiet until you resume.")
                } else if goal?.status == .archived {
                    Text("This goal is archived, so the reminder stays quiet.")
                } else if permissions.isDenied {
                    Text("Notifications are off. This reminder is saved either way.")
                }
            }
            if existing != nil {
                Section {
                    Button("Delete reminder", role: .destructive) { deleteReminder() }
                }
            }
        }
        .navigationTitle(existing == nil ? "New reminder" : "Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear(perform: load)
        .onChange(of: fireOn) { _, newValue in
            weekday = Calendar.current.component(.weekday, from: newValue)
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

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let existing {
            title = existing.title
            bodyText = existing.body
            fireOn = existing.fireOn
            weekday = existing.weekday
            recurrence = existing.recurrence
            enabled = existing.enabled
            time = timeDate(hour: existing.hour, minute: existing.minute)
        } else {
            title = checkpoint?.title ?? goal?.title ?? "Reminder"
            if let checkpoint {
                bodyText = "Continue: \(checkpoint.title)"
            } else if let goal {
                bodyText = "Continue working on \(goal.title)"
            }
            weekday = Calendar.current.component(.weekday, from: fireOn)
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
        let repository = ReminderRepository(context: context)
        do {
            if let existing {
                try repository.update(
                    existing,
                    title: title,
                    body: bodyText,
                    fireOn: fireOn,
                    hour: parts.hour ?? 9,
                    minute: parts.minute ?? 0,
                    weekday: weekday,
                    recurrence: recurrence,
                    enabled: enabled
                )
            } else {
                try repository.create(
                    goal: goal,
                    checkpoint: checkpoint,
                    title: title,
                    body: bodyText,
                    fireOn: fireOn,
                    hour: parts.hour ?? 9,
                    minute: parts.minute ?? 0,
                    weekday: weekday,
                    recurrence: recurrence,
                    enabled: enabled
                )
            }
            await NotificationScheduler.reschedule(context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteReminder() {
        if let existing {
            ReminderRepository(context: context).softDelete(existing)
        }
        Task {
            await NotificationScheduler.reschedule(context: context)
            dismiss()
        }
    }

    private func timeDate(hour: Int, minute: Int) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        parts.hour = hour
        parts.minute = minute
        return Calendar.current.date(from: parts) ?? .now
    }
}
