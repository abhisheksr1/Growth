import SwiftUI

enum StatusTint {
    static func color(for status: GoalStatus) -> Color {
        switch status {
        case .notStarted: .secondary
        case .inProgress: .accentColor
        case .paused: .orange
        case .completed: .green
        case .archived: .secondary
        }
    }
}

struct StatusBadge: View {
    var status: GoalStatus

    var body: some View {
        Label(status.title, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(StatusTint.color(for: status))
            .background(StatusTint.color(for: status).opacity(0.15), in: Capsule())
    }
}

struct DueDateText: View {
    var date: Date
    var now: Date = .now

    var body: some View {
        if DueDate.isPast(date, now: now) {
            Label("Past due · \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.orange)
        } else {
            Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ProgressMeter: View {
    var fraction: Double?
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(percentText)
                    .font(.headline.monospacedDigit())
                Spacer()
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(0, proxy.size.width * CGFloat(fraction ?? 0)))
                    }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fraction == nil ? caption : "\(percentText), \(caption)")
    }

    private var percentText: String {
        guard let fraction else { return "—" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct WeekdayPicker: View {
    @Binding var mask: Int

    private var calendar: Calendar { .current }

    var body: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let selected = WeekdayMask.contains(mask, weekday: weekday)
                Button(symbols[weekday - 1]) {
                    mask = WeekdayMask.toggling(mask, weekday: weekday)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
