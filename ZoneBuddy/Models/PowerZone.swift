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
    
    var foregroundColor: Color {
        switch self {
        case .zone1, .zone4: .black
        default: .white
        }
    }
}
