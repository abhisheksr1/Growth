import SwiftUI
import SwiftData

struct PlanSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var goal: Goal
    var onProgress: () -> Void

    @State private var text = ""
    @State private var includeDate = false
    @State private var date = Date()
    @State private var dialog: PlanDialog?
    @State private var resourcePhase: Phase?
    @State private var resourceCheckpoint: Checkpoint?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if goal.type == .numeric {
                Section {
                    Text("These checkpoints are markers. Progress still comes from the numbers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if goal.sortedPhases.isEmpty {
                Section {
                    Text("No phases yet. Add a phase when you know the first step. Until then this plan stays at 0%.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(goal.sortedPhases) { phase in
                Section {
                    ForEach(phase.sortedCheckpoints) { checkpoint in
                        CheckpointRow(checkpoint: checkpoint) {
                            _ = PlanRepository(context: context).toggleCheckpoint(checkpoint)
                            onProgress()
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                PlanRepository(context: context).softDeleteCheckpoint(checkpoint)
                            }
                        }
                        .contextMenu {
                            Button("Rename") { begin(.renameCheckpoint(checkpoint)) }
                            Button("Date") { beginDate(checkpoint) }
                            Button("Add resource") { resourceCheckpoint = checkpoint }
                            Button("Delete", role: .destructive) {
                                PlanRepository(context: context).softDeleteCheckpoint(checkpoint)
                            }
                        }
                    }
                    .onMove { offsets, offset in
                        PlanRepository(context: context).moveCheckpoints(in: phase, from: offsets, to: offset)
                    }

                    Button("Add checkpoint") { begin(.addCheckpoint(phase)) }
                    ForEach(phase.activeResources) { resource in
                        ResourceRow(resource: resource)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    PlanRepository(context: context).softDeleteResource(resource)
                                }
                            }
                    }
                    Button("Add resource") { resourcePhase = phase }
                } header: {
                    HStack {
                        Text(phase.title)
                        Spacer()
                        Menu {
                            Button("Rename") { begin(.renamePhase(phase)) }
                            Button("Delete", role: .destructive) {
                                PlanRepository(context: context).softDeletePhase(phase)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
            }
            .onMove { offsets, offset in
                PlanRepository(context: context).movePhases(in: goal, from: offsets, to: offset)
            }

            Section {
                Button("Add phase") { begin(.addPhase) }
                    .accessibilityIdentifier("plan.addPhase")
            }
        }
        .alert(dialogTitle, isPresented: Binding(
            get: { dialog != nil },
            set: { if !$0 { dialog = nil } }
        )) {
            TextField("Title", text: $text)
            if case .addCheckpoint = dialog {
                // Date is edited after the checkpoint exists.
            }
            Button(dialogConfirm, action: confirmDialog)
            Button("Cancel", role: .cancel) { dialog = nil }
        }
        .sheet(isPresented: $includeDate) {
            NavigationStack {
                Form {
                    Toggle("Target date", isOn: Binding(
                        get: { dateIncluded },
                        set: { dateIncluded = $0 }
                    ))
                    if dateIncluded {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                }
                .navigationTitle("Checkpoint date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { includeDate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveDate() }
                    }
                }
            }
        }
        .sheet(item: $resourcePhase) { phase in
            NavigationStack { ResourceEditorView(phase: phase, checkpoint: nil) }
        }
        .sheet(item: $resourceCheckpoint) { checkpoint in
            NavigationStack { ResourceEditorView(phase: nil, checkpoint: checkpoint) }
        }
        .alert("Couldn't update the plan", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @State private var dateIncluded = false
    @State private var datedCheckpoint: Checkpoint?

    private var dialogTitle: String {
        switch dialog {
        case .addPhase: "New phase"
        case .renamePhase: "Rename phase"
        case .addCheckpoint: "New checkpoint"
        case .renameCheckpoint: "Rename checkpoint"
        case nil: ""
        }
    }

    private var dialogConfirm: String {
        switch dialog {
        case .addPhase, .addCheckpoint: "Add"
        default: "Save"
        }
    }

    private func begin(_ next: PlanDialog) {
        switch next {
        case .addPhase, .addCheckpoint:
            text = ""
        case .renamePhase(let phase):
            text = phase.title
        case .renameCheckpoint(let checkpoint):
            text = checkpoint.title
        }
        dialog = next
    }

    private func beginDate(_ checkpoint: Checkpoint) {
        datedCheckpoint = checkpoint
        dateIncluded = checkpoint.targetDate != nil
        date = checkpoint.targetDate ?? .now
        includeDate = true
    }

    private func confirmDialog() {
        do {
            switch dialog {
            case .addPhase:
                try PlanRepository(context: context).addPhase(to: goal, title: text)
            case .renamePhase(let phase):
                try PlanRepository(context: context).renamePhase(phase, title: text)
            case .addCheckpoint(let phase):
                try PlanRepository(context: context).addCheckpoint(to: phase, title: text)
            case .renameCheckpoint(let checkpoint):
                try PlanRepository(context: context).renameCheckpoint(checkpoint, title: text)
            case nil:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        dialog = nil
    }

    private func saveDate() {
        if let datedCheckpoint {
            PlanRepository(context: context).setCheckpointTarget(datedCheckpoint, date: dateIncluded ? date : nil)
        }
        includeDate = false
    }
}

private enum PlanDialog: Identifiable {
    case addPhase
    case renamePhase(Phase)
    case addCheckpoint(Phase)
    case renameCheckpoint(Checkpoint)

    var id: String {
        switch self {
        case .addPhase: "add-phase"
        case .renamePhase(let phase): "rename-phase-\(phase.id)"
        case .addCheckpoint(let phase): "add-checkpoint-\(phase.id)"
        case .renameCheckpoint(let checkpoint): "rename-checkpoint-\(checkpoint.id)"
        }
    }
}

struct CheckpointRow: View {
    var checkpoint: Checkpoint
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: checkpoint.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(checkpoint.completedAt == nil ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("checkpoint.toggle.\(checkpoint.title)")
            .accessibilityLabel(checkpoint.completedAt == nil ? "Mark \(checkpoint.title) complete" : "Reopen \(checkpoint.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(checkpoint.title)
                    .strikethrough(checkpoint.completedAt != nil, color: .secondary)
                    .foregroundStyle(checkpoint.completedAt == nil ? Color.primary : Color.secondary)
                if let date = checkpoint.targetDate {
                    DueDateText(date: date)
                }
                if !checkpoint.notes.isEmpty {
                    Text(checkpoint.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(checkpoint.activeResources) { resource in
                    ResourceRow(resource: resource)
                }
            }
        }
    }
}

struct ResourceRow: View {
    var resource: ResourceLink

    var body: some View {
        if let url = resource.url {
            Link(destination: url) {
                Label {
                    VStack(alignment: .leading) {
                        Text(resource.title)
                        if !resource.note.isEmpty {
                            Text(resource.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "link")
                }
            }
        } else {
            Text(resource.title)
        }
    }
}

struct ResourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var phase: Phase?
    var checkpoint: Checkpoint?

    @State private var title = ""
    @State private var url = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Web address", text: $url)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            TextField("Note", text: $note, axis: .vertical)
        }
        .navigationTitle("Resource")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
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
        do {
            try PlanRepository(context: context).addResource(
                title: title,
                url: url,
                note: note,
                phase: phase,
                checkpoint: checkpoint
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
