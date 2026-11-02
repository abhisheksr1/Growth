import SwiftUI
import SwiftData

struct ActivityTimeline: View {
    var goal: Goal

    private var events: [ActivityEvent] {
        (goal.activityEvents ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        if events.isEmpty {
            Section {
                Text("Changes to this goal will gather here.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: event.type.symbolName)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.type.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(event.summary)
                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
