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
    func foregroundColorsForLightBackgrounds() {
        // Zone 1 (gray) and Zone 4 (yellow) should have black foreground
        #expect(PowerZone.zone1.foregroundColor == .black)
        #expect(PowerZone.zone4.foregroundColor == .black)
    }

    @Test
    func foregroundColorsForDarkBackgrounds() {
        // All other zones should have white foreground
        #expect(PowerZone.zone2.foregroundColor == .white)
        #expect(PowerZone.zone3.foregroundColor == .white)
        #expect(PowerZone.zone5.foregroundColor == .white)
        #expect(PowerZone.zone6.foregroundColor == .white)
        #expect(PowerZone.zone7.foregroundColor == .white)
    }
}
