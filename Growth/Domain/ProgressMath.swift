import Foundation

enum ProgressMath {
    /// Completed checkpoints over the total. An empty plan is 0%, and it is not complete.
    static func milestoneFraction(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    static func milestoneIsComplete(completed: Int, total: Int) -> Bool {
        total > 0 && completed == total
    }

    /// Increase: (current - start) / (target - start). Decrease: (start - current) / (start - target).
    /// Returns nil when the span is zero or points the wrong way, so callers never divide by zero.
    static func numericFraction(
        direction: NumericDirection,
        start: Double,
        current: Double,
        target: Double
    ) -> Double? {
        let span: Double
        let traveled: Double
        switch direction {
        case .increase:
            span = target - start
            traveled = current - start
        case .decrease:
            span = start - target
            traveled = start - current
        }
        guard span > 0 else { return nil }
        return min(max(traveled / span, 0), 1)
    }

    static func numericTargetReached(
        direction: NumericDirection,
        start: Double,
        current: Double,
        target: Double
    ) -> Bool {
        switch direction {
        case .increase:
            guard target > start else { return false }
            return current >= target
        case .decrease:
            guard target < start else { return false }
            return current <= target
        }
    }

    static func ratio(completed: Int, expected: Int) -> Double {
        guard expected > 0 else { return 0 }
        return min(max(Double(completed) / Double(expected), 0), 1)
    }
}
