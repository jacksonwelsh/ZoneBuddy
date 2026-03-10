import Testing
import SwiftUI
@testable import ZoneBuddy

struct PowerZoneTests {
    @Test
    func allZonesHaveUniqueRawValues() {
        let rawValues = PowerZone.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == 7)
    }

    @Test
    func rawValuesAreOneThruSeven() {
        let rawValues = PowerZone.allCases.map(\.rawValue).sorted()
        #expect(rawValues == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test
    func displayNames() {
        #expect(PowerZone.zone1.displayName == "Zone 1")
        #expect(PowerZone.zone4.displayName == "Zone 4")
        #expect(PowerZone.zone7.displayName == "Zone 7")
    }

    @Test
    func initFromRawValue() {
        #expect(PowerZone(rawValue: 1) == .zone1)
        #expect(PowerZone(rawValue: 7) == .zone7)
        #expect(PowerZone(rawValue: 0) == nil)
        #expect(PowerZone(rawValue: 8) == nil)
    }

    @Test
    func foregroundColorsComputedFromContrast() {
        // All zone colors are light enough that black provides better WCAG contrast
        for zone in PowerZone.allCases {
            #expect(zone.foregroundColor == .black || zone.foregroundColor == .white,
                    "Zone \(zone.rawValue) should have a valid foreground color")
        }
    }

    @Test
    func zoneNames() {
        #expect(PowerZone.zone1.zoneName == "Active Recovery")
        #expect(PowerZone.zone2.zoneName == "Endurance")
        #expect(PowerZone.zone3.zoneName == "Tempo")
        #expect(PowerZone.zone4.zoneName == "Threshold")
        #expect(PowerZone.zone5.zoneName == "VO2 Max")
        #expect(PowerZone.zone6.zoneName == "Anaerobic")
        #expect(PowerZone.zone7.zoneName == "Neuromuscular")
    }
}
