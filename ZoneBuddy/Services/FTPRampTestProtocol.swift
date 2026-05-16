import Foundation

/// Smart-trainer ramp test for estimating FTP.
///
/// Protocol: 5-min easy warmup → progressive 1-min steps starting at
/// `rampStartWatts`, increasing by `rampStepWatts` each minute until either
/// the rider gives up or the configured cap is reached. FTP is estimated as
/// **75% × the best 1-minute average power** observed during the ramp,
/// following the FTP↔MAP correlation Ric Stern characterised in the late
/// '90s (FTP ≈ 72–77% of MAP; 75% is the value Zwift and TrainerRoad use).
///
/// This protocol is intended to run with a connected, ERG-capable FTMS
/// trainer: each ramp step carries an explicit `targetWatts`, and the
/// workout engine drives the trainer to that target. The rider just spins.
/// Without a controllable trainer the picker in `FTPTestIntroView` does not
/// offer this option; using it with a non-controllable bike would require
/// manual gear changes per step and is unsupported.
enum FTPRampTestProtocol {
    static let warmupDuration: Int = 5 * 60
    static let stepDuration: Int = 60
    static let cooldownDuration: Int = 5 * 60
    static let rampStartWatts: Int = 100
    static let rampStepWatts: Int = 20
    /// Hard cap on ramp target — past this we stop generating steps. Even
    /// elite riders blow up well before this on a 20W/min ramp.
    static let rampMaxWatts: Int = 500

    static let workoutName: String = "FTP Ramp Test"

    /// Index of the first ramp step (inclusive). Index 0 is warmup.
    static let firstRampIntervalIndex: Int = 1

    /// Number of generated ramp steps from `rampStartWatts` to `rampMaxWatts`.
    static var rampStepCount: Int {
        ((rampMaxWatts - rampStartWatts) / rampStepWatts) + 1
    }

    /// Index of the cooldown interval. Equal to firstRampIntervalIndex + rampStepCount.
    static var cooldownIntervalIndex: Int {
        firstRampIntervalIndex + rampStepCount
    }

    static func makeIntervals() -> [Interval] {
        var intervals: [Interval] = []
        intervals.append(Interval(zone: nil, duration: warmupDuration, sortOrder: 0))

        var watts = rampStartWatts
        var sortOrder = 1
        while watts <= rampMaxWatts {
            intervals.append(Interval(zone: nil, duration: stepDuration, sortOrder: sortOrder, targetWatts: watts))
            watts += rampStepWatts
            sortOrder += 1
        }

        intervals.append(Interval(zone: nil, duration: cooldownDuration, sortOrder: sortOrder))
        return intervals
    }

    /// FTP = round(0.75 × max 1-minute rolling avg power) across the ramp samples.
    /// `samplePowers` should be 1Hz instantaneous power readings captured during
    /// the ramp window. Returns nil for inputs that can't yield a single 60-sample window.
    static func computeFTP(fromSamplePowers samplePowers: [Int]) -> Int? {
        guard let best = bestMinutePower(fromSamplePowers: samplePowers) else { return nil }
        return Int((Double(best) * 0.75).rounded())
    }

    /// Best 1-minute rolling average (60 consecutive samples at 1Hz). Returns nil if
    /// fewer than 60 samples were captured.
    static func bestMinutePower(fromSamplePowers samplePowers: [Int]) -> Int? {
        let window = 60
        guard samplePowers.count >= window else { return nil }
        var sum = samplePowers.prefix(window).reduce(0, +)
        var best = sum
        for i in window..<samplePowers.count {
            sum += samplePowers[i] - samplePowers[i - window]
            if sum > best { best = sum }
        }
        return Int((Double(best) / Double(window)).rounded())
    }

    static func phaseLabel(forIndex index: Int) -> String {
        if index == 0 { return "Warmup" }
        if index >= cooldownIntervalIndex { return "Cooldown" }
        let step = index - firstRampIntervalIndex + 1
        return "Ramp Step \(step)"
    }
}
