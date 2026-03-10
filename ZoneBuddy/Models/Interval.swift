import Foundation
import SwiftData

@Model
final class Interval {
    var zoneRawValue: Int?
    var duration: Int = 60
    var sortOrder: Int = 0
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

    init(zone: PowerZone?, duration: Int, sortOrder: Int) {
        self.zoneRawValue = zone?.rawValue
        self.duration = duration
        self.sortOrder = sortOrder
    }

    static func warmup(duration: Int, sortOrder: Int) -> Interval {
        Interval(zone: nil, duration: duration, sortOrder: sortOrder)
    }
}
