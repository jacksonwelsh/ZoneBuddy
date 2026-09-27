/// Manual power changes follow the 5 W grid while preserving prescribed targets
/// until the rider makes an adjustment.
enum TrainerPowerSteps {
    static func adjacent(to watts: Int, increasing: Bool) -> Int {
        let lower = Int((Double(watts) / 5).rounded(.down)) * 5
        return increasing ? lower + 5 : (lower == watts ? lower - 5 : lower)
    }

    static func target(start: Int, steps: Int, range: ClosedRange<Int>) -> Int {
        guard steps != 0 else { return min(max(start, range.lowerBound), range.upperBound) }
        let first = adjacent(to: start, increasing: steps > 0)
        let remaining = steps > 0 ? steps - 1 : steps + 1
        return min(max(first + remaining * 5, range.lowerBound), range.upperBound)
    }
}
