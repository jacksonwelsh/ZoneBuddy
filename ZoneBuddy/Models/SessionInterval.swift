import Foundation
import SwiftData

/// Immutable snapshot of a single interval as it was at the moment a workout was completed.
/// Owned by a `WorkoutSession`; cascade-deleted with it. Intentionally decoupled from
/// the live `Interval` model so editing or deleting a workout template never alters history.
@Model
final class SessionInterval {
    var zoneRawValue: Int?
    var duration: Int = 60
    var sortOrder: Int = 0
    var session: WorkoutSession?

    var zone: PowerZone? {
        guard let raw = zoneRawValue else { return nil }
        return PowerZone(rawValue: raw)
    }

    var isWarmup: Bool {
        zoneRawValue == nil
    }

    var baseLabel: String {
        if isWarmup { return "Warmup" }
        return zone?.zoneName ?? ""
    }

    init(zone: PowerZone?, duration: Int, sortOrder: Int) {
        self.zoneRawValue = zone?.rawValue
        self.duration = duration
        self.sortOrder = sortOrder
    }
}
