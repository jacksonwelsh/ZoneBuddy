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
        switch self {
        case .zone1: Color(red: 0.63, green: 0.63, blue: 0.63)
        case .zone2: Color(red: 0.00, green: 0.47, blue: 1.00)
        case .zone3: Color(red: 0.00, green: 0.80, blue: 0.00)
        case .zone4: Color(red: 1.00, green: 0.84, blue: 0.00)
        case .zone5: Color(red: 1.00, green: 0.55, blue: 0.00)
        case .zone6: Color(red: 1.00, green: 0.13, blue: 0.00)
        case .zone7: Color(red: 0.55, green: 0.00, blue: 1.00)
        }
    }

    var displayName: String {
        "Zone \(rawValue)"
    }

    var foregroundColor: Color {
        switch self {
        case .zone1, .zone4: .black
        default: .white
        }
    }
}
