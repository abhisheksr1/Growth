import SwiftUI
import SwiftData

struct ReflectionSection: View {
    @Environment(\.modelContext) private var context
    var goal: Goal
    var onRecalibrate: () -> Void

    @State private var showEditor = false

    var body: some View {
        Group {
            reflectionContent
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack { ReflectionEditorView(goal: goal, presetFeeling: nil) }
        }
    }

    @ViewBuilder
    private var reflectionContent: some View {
        Section {
            Button("New reflection") { showEditor = true }
            Button("Recalibrate") { onRecalibrate() }
        } footer: {
            Text("A reflection stays with this goal. Recalibrate is the place to change the plan, and it keeps the history.")
        }
        if goal.activeReflections.isEmpty && goal.activeRecalibrations.isEmpty {
            Section {
                Text("Nothing written yet. Feeling is the only required part of a reflection.")
                    .foregroundStyle(.secondary)
            }
        }
        if !goal.activeReflections.isEmpty {
            Section("Reflections") {
                ForEach(goal.activeReflections) { reflection in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(reflection.feeling.title, systemImage: reflection.feeling.symbolName)
                            .font(.subheadline.weight(.semibold))
                        Text(reflection.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        reflectionLine("Expected", reflection.expectedText)
                        reflectionLine("What happened", reflection.happenedText)
                        reflectionLine("What worked", reflection.workedText)
                        reflectionLine("In the way", reflection.inTheWayText)
                        reflectionLine("Learned", reflection.learnedText)
                        reflectionLine("I'll change", reflection.nextChangeText)
                    }
                    .padding(.vertical, 4)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            ReflectionRepository(context: context).softDelete(reflection)
                        }
                    }
                }
            }
        }
        if !goal.activeRecalibrations.isEmpty {
            Section("Recalibrations") {
                ForEach(goal.activeRecalibrations) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !record.situation.isEmpty {
                            Text(record.situation)
                        }
                        if !record.reflectionNote.isEmpty {
                            Text(record.reflectionNote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reflectionLine(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline)
        }
    }
}

struct ReflectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var goal: Goal
    var presetFeeling: Feeling?

    @State private var feeling: Feeling = .okay
    @State private var expected = ""
    @State private var happened = ""
    @State private var worked = ""
    @State private var inTheWay = ""
    @State private var learned = ""
    @State private var nextChange = ""
    @State private var didApplyPreset = false

    var body: some View {
        Form {
            Picker("Feeling", selection: $feeling) {
                ForEach(Feeling.allCases) { item in
                    Label(item.title, systemImage: item.symbolName).tag(item)
                }
            }
            prompt("What did you expect?", text: $expected)
            prompt("What actually happened?", text: $happened)
            prompt("What worked?", text: $worked)
            prompt("What got in the way?", text: $inTheWay)
            prompt("What did you learn?", text: $learned)
            prompt("What will you change?", text: $nextChange)
        }
        .navigationTitle("Reflection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .accessibilityIdentifier("reflection.save")
            }
        }
        .onAppear {
            guard !didApplyPreset else { return }
            didApplyPreset = true
            if let presetFeeling { feeling = presetFeeling }
        }
    }

    private func prompt(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical)
            .lineLimit(2...5)
    }

    private func save() {
        _ = ReflectionRepository(context: context).create(
            goal: goal,
            feeling: feeling,
            expected: expected,
            happened: happened,
            worked: worked,
            inTheWay: inTheWay,
            learned: learned,
            nextChange: nextChange
        )
        dismiss()
    }
}
