import SwiftUI
import SwiftData

struct JournalListView: View {
    @Query(sort: \JournalEntry.updatedAt, order: .reverse) private var stored: [JournalEntry]
    @State private var search = ""
    @State private var showEditor = false

    private var entries: [JournalEntry] {
        JournalRepository.filtered(stored, search: search)
    }

    var body: some View {
        NavigationStack {
            Group {
                if stored.filter({ $0.deletedAt == nil }).isEmpty {
                    EmptyStateView(
                        systemImage: "book",
                        title: "No journal entries",
                        message: "An entry can stand on its own, or point at one or more goals. There's no daily requirement.",
                        actionTitle: "New entry",
                        action: { showEditor = true }
                    )
                } else if entries.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List {
                        ForEach(entries) { entry in
                            NavigationLink {
                                JournalEditorView(entry: entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.headline)
                                    if !entry.body.isEmpty {
                                        Text(entry.body)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    HStack {
                                        Text(entry.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                        if let names = linkedNames(entry) {
                                            Text(names)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    delete(entry)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Journal")
            .searchable(text: $search, prompt: "Title or text")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("journal.new")
                }
            }
            .sheet(isPresented: $showEditor) {
                NavigationStack { JournalEditorView(entry: nil) }
            }
        }
    }

    @Environment(\.modelContext) private var context

    private func linkedNames(_ entry: JournalEntry) -> String? {
        let names = (entry.goals ?? []).filter { $0.deletedAt == nil }.map(\.title)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private func delete(_ entry: JournalEntry) {
        JournalRepository(context: context).softDelete(entry)
    }
}

struct JournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.title) private var goals: [Goal]

    private let existing: JournalEntry?
    @State private var title: String
    @State private var bodyText: String
    @State private var selected: Set<UUID>
    @State private var errorMessage: String?

    init(entry: JournalEntry?) {
        existing = entry
        _title = State(initialValue: entry?.title ?? "")
        _bodyText = State(initialValue: entry?.body ?? "")
        _selected = State(initialValue: Set((entry?.goals ?? []).map(\.id)))
    }

    private var linkableGoals: [Goal] {
        goals.filter { $0.deletedAt == nil && $0.status != .archived }
    }

    var body: some View {
        Form {
            TextField("Title", text: $title)
                .accessibilityIdentifier("journal.title")
            TextField("What's on your mind?", text: $bodyText, axis: .vertical)
                .lineLimit(6...16)
                .accessibilityIdentifier("journal.body")
            Section("Linked goals") {
                if linkableGoals.isEmpty {
                    Text("No goals to link yet. This entry can still stand on its own.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(linkableGoals) { goal in
                        Button {
                            if selected.contains(goal.id) {
                                selected.remove(goal.id)
                            } else {
                                selected.insert(goal.id)
                            }
                        } label: {
                            HStack {
                                Text(goal.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(goal.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "New entry" : "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .accessibilityIdentifier("journal.save")
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
        let linked = linkableGoals.filter { selected.contains($0.id) }
        do {
            try JournalRepository(context: context).save(
                existing: existing,
                title: title,
                body: bodyText,
                goals: linked
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
