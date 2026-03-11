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

    /// Standard Peloton Power Zone percentage ranges relative to FTP.
    private var ftpPercentRange: ClosedRange<Double> {
        switch self {
        case .zone1: return 0...0.55
        case .zone2: return 0.55...0.75
        case .zone3: return 0.76...0.90
        case .zone4: return 0.91...1.05
        case .zone5: return 1.06...1.20
        case .zone6: return 1.21...1.50
        case .zone7: return 1.50...3.0
        }
    }

    /// Watt range for this zone given an FTP value.
    func wattRange(ftp: Int) -> ClosedRange<Int> {
        let lower = Int((ftpPercentRange.lowerBound * Double(ftp)).rounded())
        let upper = Int((ftpPercentRange.upperBound * Double(ftp)).rounded())
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
        if pct <= 0.55 { return .zone1 }
        if pct <= 0.75 { return .zone2 }
        if pct <= 0.90 { return .zone3 }
        if pct <= 1.05 { return .zone4 }
        if pct <= 1.20 { return .zone5 }
        if pct <= 1.50 { return .zone6 }
        return .zone7
    }
}
