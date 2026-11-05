import SwiftUI
import SwiftData

struct RoadmapReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var goal: Goal
    @State private var draft: RoadmapDraft
    @State private var askReplace = false
    @State private var errorMessage: String?

    init(goal: Goal, draft: RoadmapDraft) {
        self.goal = goal
        _draft = State(initialValue: draft)
    }

    var body: some View {
        List {
            Section {
                Text("\(draft.phases.count) phases · \(draft.checkpointCount) checkpoints")
                    .font(.subheadline)
                if !draft.suggestedTitle.isEmpty, draft.suggestedTitle != goal.title {
                    Button("Rename this goal to \"\(draft.suggestedTitle)\"") {
                        renameGoal()
                    }
                }
                if !draft.summary.isEmpty {
                    Text(draft.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(draft.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if draft.phases.isEmpty {
                Section {
                    Text("Nothing from this document was turned into a plan.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach($draft.phases) { $phase in
                Section {
                    TextField("Phase", text: $phase.title, axis: .vertical)
                    if !phase.notes.isEmpty {
                        Text(phase.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($phase.checkpoints) { $checkpoint in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Checkpoint", text: $checkpoint.title, axis: .vertical)
                            if !checkpoint.notes.isEmpty {
                                Text(checkpoint.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            ForEach(checkpoint.links, id: \.url) { link in
                                Text(link.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                phase.checkpoints.removeAll { $0.id == checkpoint.id }
                            }
                        }
                    }
                    Button("Remove phase", role: .destructive) {
                        draft.phases.removeAll { $0.id == phase.id }
                    }
                }
            }
        }
        .navigationTitle("Review plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") { beginImport() }
                    .disabled(!draft.canImport)
            }
        }
        .confirmationDialog("This goal already has a plan", isPresented: $askReplace, titleVisibility: .visible) {
            Button("Replace the plan", role: .destructive) { apply(.replace) }
            Button("Add to the plan") { apply(.append) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't import the plan", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func beginImport() {
        if goal.sortedPhases.isEmpty {
            apply(.replace)
        } else {
            askReplace = true
        }
    }

    private func apply(_ mode: PlanImportMode) {
        do {
            try PlanRepository(context: context).importRoadmap(draft, into: goal, mode: mode)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameGoal() {
        let title = draft.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        goal.title = String(title.prefix(120))
        goal.updatedAt = .now
        try? StoreSaving.save(context)
    }
}
