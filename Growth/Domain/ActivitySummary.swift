import Foundation

enum ActivitySummary {
    static func created(title: String) -> String {
        "Created \(title)"
    }

    static func status(from: GoalStatus, to: GoalStatus) -> String {
        "\(from.title) → \(to.title)"
    }

    static func checkpointCompleted(_ title: String) -> String {
        "Completed \(title)"
    }

    static func checkpointReopened(_ title: String) -> String {
        "Reopened \(title)"
    }

    static func progress(value: Double, unit: String) -> String {
        let number = DecimalText.string(value)
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Updated to \(number)" : "Updated to \(number) \(trimmed)"
    }

    static func habit(on day: Date, calendar: Calendar = .current) -> String {
        let label = day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(calendar.locale ?? .current))
        return "Logged \(label)"
    }

    static func reminder(_ title: String, change: String) -> String {
        "\(change) \(title)"
    }

    static func reflection() -> String {
        "Added a reflection"
    }

    static func roadmap(_ detail: String) -> String {
        detail
    }

    static func recalibrated() -> String {
        "Recalibrated the plan. Earlier history is unchanged."
    }
}

struct ActivitySnapshot: Codable, Equatable, Sendable {
    var goalTitle: String
    var before: String?
    var after: String?
    var detail: String?

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func decode(_ text: String) -> ActivitySnapshot? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ActivitySnapshot.self, from: data)
    }
}

enum CheckInDue {
    static func isDue(
        enabled: Bool,
        weekday: Int,
        hasSessionOnDay: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard enabled, !hasSessionOnDay else { return false }
        return calendar.component(.weekday, from: now) == weekday
    }
}
