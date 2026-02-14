import Foundation
import SwiftData

@Model
final class Interval {
    var zoneRawValue: Int?
    var duration: Int
    var sortOrder: Int
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

    init(zone: PowerZone?, duration: Int, sortOrder: Int) {
        self.zoneRawValue = zone?.rawValue
        self.duration = duration
        self.sortOrder = sortOrder
    }

    static func warmup(duration: Int, sortOrder: Int) -> Interval {
        Interval(zone: nil, duration: duration, sortOrder: sortOrder)
    }
}
