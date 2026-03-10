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
}
