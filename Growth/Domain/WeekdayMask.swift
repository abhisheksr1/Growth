import Foundation

enum WeekdayMask {
    static func contains(_ mask: Int, weekday: Int) -> Bool {
        guard (1...7).contains(weekday) else { return false }
        return mask & (1 << (weekday - 1)) != 0
    }

    static func toggling(_ mask: Int, weekday: Int) -> Int {
        guard (1...7).contains(weekday) else { return mask }
        return mask ^ (1 << (weekday - 1))
    }

    /// Monday through Friday when Sunday is weekday 1, matching `Calendar`.
    static let weekdays = 62
}
