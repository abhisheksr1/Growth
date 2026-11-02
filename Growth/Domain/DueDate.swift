import Foundation

enum DueDate {
    /// A date is past due only once the local day has ended. Today is not past due.
    static func isPast(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }
}
