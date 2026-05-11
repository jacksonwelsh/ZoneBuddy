import Foundation

/// Locale-aware formatting for cycling metrics. Centralizes the km/mi and km/h/mph
/// branching so adding a new unit (or supporting user-overridden preferences) is one edit.
enum UnitFormatting {
    /// True when the current locale uses metric units.
    static var usesMetric: Bool {
        Locale.current.measurementSystem != .us
    }

    /// Display unit for distance ("km" or "mi"). Same string used by every metric tile.
    static var distanceUnit: String {
        usesMetric ? "km" : "mi"
    }

    /// Display unit for speed ("km/h" or "mph").
    static var speedUnit: String {
        usesMetric ? "km/h" : "mph"
    }

    /// Format a distance in meters into a locale-appropriate string (no unit suffix).
    /// - Parameters:
    ///   - meters: Source distance.
    ///   - precision: Decimal places. Most tiles use 1; the metrics tile uses 2.
    static func distance(meters: Double, precision: Int = 1) -> String {
        let value = usesMetric ? meters / 1000.0 : meters / 1609.344
        return String(format: "%.\(precision)f", value)
    }

    /// Format a speed in km/h (the unit the FTMS bike reports) into a locale-appropriate string.
    static func speed(kmh: Double, precision: Int = 1) -> String {
        let value = usesMetric ? kmh : kmh * 0.621371
        return String(format: "%.\(precision)f", value)
    }
}
