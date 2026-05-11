import SwiftUI

/// Standard 5-zone heart rate model based on max HR.
enum HeartRateZone: Int, CaseIterable, Identifiable {
    case zone1 = 1 // 50-60%
    case zone2 = 2 // 60-70%
    case zone3 = 3 // 70-80%
    case zone4 = 4 // 80-90%
    case zone5 = 5 // 90-100%

    var id: Int { rawValue }

    var color: Color {
        switch self {
        case .zone1: .blue
        case .zone2: .green
        case .zone3: .yellow
        case .zone4: .orange
        case .zone5: .red
        }
    }

    var displayName: String {
        "Zone \(rawValue)"
    }

    var zoneName: String {
        switch self {
        case .zone1: "Recovery"
        case .zone2: "Aerobic"
        case .zone3: "Tempo"
        case .zone4: "Threshold"
        case .zone5: "Max"
        }
    }

    func bpmRange(maxHR: Int) -> ClosedRange<Int> {
        let (lower, upper): (Double, Double) = switch self {
        case .zone1: (0.50, 0.60)
        case .zone2: (0.60, 0.70)
        case .zone3: (0.70, 0.80)
        case .zone4: (0.80, 0.90)
        case .zone5: (0.90, 1.00)
        }
        return Int((lower * Double(maxHR)).rounded())...Int((upper * Double(maxHR)).rounded())
    }

    static func zone(forBPM bpm: Int, maxHR: Int) -> HeartRateZone? {
        guard maxHR > 0 && bpm >= 0 else { return nil }
        let pct = Double(bpm) / Double(maxHR)
        if pct < 0.60 { return .zone1 }
        if pct < 0.70 { return .zone2 }
        if pct < 0.80 { return .zone3 }
        if pct < 0.90 { return .zone4 }
        return .zone5
    }
}
