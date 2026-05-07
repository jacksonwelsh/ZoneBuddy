import Foundation
import SwiftData

/// Defines the structure and calculations for the in-app 20-minute FTP test.
///
/// Protocol: 15 min progressive warmup → 20 min sustained max effort → 10 min cooldown.
/// FTP is calculated as 95% of the average power held during the 20-minute test interval.
enum FTPTestProtocol {
    static let warmupDuration: Int = 15 * 60
    static let testDuration: Int = 20 * 60
    static let cooldownDuration: Int = 10 * 60

    /// Index of the test interval inside `makeIntervals()`. The view model uses this to
    /// scope per-interval power-sample collection for the FTP calculation.
    static let testIntervalIndex: Int = 1

    static let workoutName: String = "FTP Test"

    static func makeIntervals() -> [Interval] {
        [
            Interval(zone: nil, duration: warmupDuration, sortOrder: 0),
            Interval(zone: nil, duration: testDuration, sortOrder: 1),
            Interval(zone: nil, duration: cooldownDuration, sortOrder: 2),
        ]
    }

    static func computeFTP(avgPower: Int) -> Int {
        Int((Double(avgPower) * 0.95).rounded())
    }

    static func phaseLabel(forIndex index: Int) -> String {
        switch index {
        case 0: return "Warmup"
        case 1: return "FTP Test"
        case 2: return "Cooldown"
        default: return ""
        }
    }
}
