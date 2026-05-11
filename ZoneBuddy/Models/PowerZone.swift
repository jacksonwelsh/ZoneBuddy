import SwiftUI

enum PowerZone: Int, Codable, CaseIterable, Identifiable, Sendable {
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5
    case zone6 = 6
    case zone7 = 7

    var id: Int { rawValue }

    var color: Color {
        Color("Zone\(rawValue)Color")
    }

    /// Contrast-safe color for use as text on the workout screen.
    /// Returns a darker shade in light mode (≥4.5:1 on white) and the
    /// original vibrant color in dark mode — automatically via asset catalog.
    var labelColor: Color {
        Color("Zone\(rawValue)LabelColor")
    }

    var displayName: String {
        "Zone \(rawValue)"
    }

    var zoneName: String {
        switch self {
        case .zone1: "Active Recovery"
        case .zone2: "Endurance"
        case .zone3: "Tempo"
        case .zone4: "Threshold"
        case .zone5: "VO2 Max"
        case .zone6: "Anaerobic"
        case .zone7: "Neuromuscular"
        }
    }

    var foregroundColor: Color {
        let resolved = color.resolve(in: EnvironmentValues())
        let r = Double(resolved.red)
        let g = Double(resolved.green)
        let b = Double(resolved.blue)

        func linearize(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)

        let contrastWithWhite = 1.05 / (luminance + 0.05)
        let contrastWithBlack = (luminance + 0.05) / 0.05
        return contrastWithBlack > contrastWithWhite ? .black : .white
    }

    // MARK: - FTP-Based Calculations

    /// Inclusive upper bound % of FTP for this zone (Peloton Power Zones).
    /// Single source of truth: both `wattRange` and `zone(forPower:)` derive from this so
    /// the displayed watt range always matches the zone the same power classifies into.
    private var upperBoundPercent: Double {
        switch self {
        case .zone1: 0.55
        case .zone2: 0.75
        case .zone3: 0.90
        case .zone4: 1.05
        case .zone5: 1.20
        case .zone6: 1.50
        case .zone7: 3.0
        }
    }

    /// Watt range for this zone given an FTP value. Adjacent zones' ranges are continuous
    /// (no overlap, no gap): `zoneN.upperBound + 1 == zoneN+1.lowerBound`.
    func wattRange(ftp: Int) -> ClosedRange<Int> {
        let upper = Int((upperBoundPercent * Double(ftp)).rounded())
        let lower: Int
        if let previous = PowerZone(rawValue: rawValue - 1) {
            lower = Int((previous.upperBoundPercent * Double(ftp)).rounded()) + 1
        } else {
            lower = 0
        }
        return lower...upper
    }

    /// Human-readable watt range description, e.g. "165-200W".
    func rangeDescription(ftp: Int) -> String {
        let range = wattRange(ftp: ftp)
        switch self {
        case .zone1:
            return "<\(range.upperBound)W"
        case .zone7:
            return ">\(range.lowerBound)W"
        default:
            return "\(range.lowerBound)-\(range.upperBound)W"
        }
    }

    /// Whether the given power falls within this zone for a given FTP.
    func contains(power: Int, ftp: Int) -> Bool {
        Self.zone(forPower: power, ftp: ftp) == self
    }

    /// Determine which zone a given power output falls into.
    static func zone(forPower power: Int, ftp: Int) -> PowerZone? {
        guard ftp > 0 && power >= 0 else { return nil }
        let pct = Double(power) / Double(ftp)
        for zone in PowerZone.allCases {
            if pct <= zone.upperBoundPercent { return zone }
        }
        return .zone7
    }
}
