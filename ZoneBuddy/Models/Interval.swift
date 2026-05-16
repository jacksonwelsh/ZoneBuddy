import Foundation
import SwiftData

@Model
final class Interval {
    var zoneRawValue: Int?
    var duration: Int = 60
    var sortOrder: Int = 0
    /// Explicit ERG target in watts for this interval. When set, the workout
    /// engine drives the trainer to this value instead of the zone-band midpoint.
    /// Currently used by the ramp FTP test to step targets up each minute.
    var targetWatts: Int?
    var workout: Workout?

    var zone: PowerZone? {
        get {
            guard let raw = zoneRawValue else { return nil }
            return PowerZone(rawValue: raw)
        }
        set {
            zoneRawValue = newValue?.rawValue
        }
    }

    var isWarmup: Bool {
        zoneRawValue == nil
    }

    var baseLabel: String {
        if isWarmup { return "Warmup" }
        return zone?.zoneName ?? ""
    }

    var spokenLabel: String {
        if isWarmup { return "Warmup" }
        return zone?.displayName ?? ""
    }

    init(zone: PowerZone?, duration: Int, sortOrder: Int, targetWatts: Int? = nil) {
        self.zoneRawValue = zone?.rawValue
        self.duration = duration
        self.sortOrder = sortOrder
        self.targetWatts = targetWatts
    }

    static func warmup(duration: Int, sortOrder: Int) -> Interval {
        Interval(zone: nil, duration: duration, sortOrder: sortOrder)
    }
}
