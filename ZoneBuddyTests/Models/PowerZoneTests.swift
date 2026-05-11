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

    // MARK: - FTP-Based Calculations

    @Test(arguments: [100, 200, 300])
    func wattRangesAreContinuousAndNonOverlapping(ftp: Int) {
        // Adjacent zones must satisfy zoneN.upperBound + 1 == zoneN+1.lowerBound so
        // every integer watt value maps to exactly one zone.
        var previousUpper: Int? = nil
        for zone in PowerZone.allCases {
            let range = zone.wattRange(ftp: ftp)
            if let prev = previousUpper {
                #expect(range.lowerBound == prev + 1, "Zone \(zone.rawValue) lower (\(range.lowerBound)) should equal previous upper (\(prev)) + 1 at FTP \(ftp)")
            } else {
                #expect(range.lowerBound == 0, "Zone 1 should start at 0W")
            }
            #expect(range.upperBound >= range.lowerBound, "Zone \(zone.rawValue) range should be non-empty at FTP \(ftp)")
            previousUpper = range.upperBound
        }
    }

    @Test
    func wattRangeAtFTP200() {
        let ftp = 200
        // Zone 1: 0..55% = 0-110W
        #expect(PowerZone.zone1.wattRange(ftp: ftp) == 0...110)
        // Zone 2: starts 1W above zone1's upper bound
        #expect(PowerZone.zone2.wattRange(ftp: ftp) == 111...150)
        // Zone 4: 91-105% = 181-210W (continuous from zone3's 180W upper)
        #expect(PowerZone.zone4.wattRange(ftp: ftp) == 181...210)
    }

    @Test
    func wattRangeAndZoneForPowerAgree() {
        // Regression: previously `wattRange` produced gaps between zones (e.g. 151W at FTP=200
        // fell into no displayed zone, but `zone(forPower:)` classified it as zone3). Verify
        // every integer watt in a zone's `wattRange` classifies into that same zone.
        let ftp = 200
        for zone in PowerZone.allCases {
            let range = zone.wattRange(ftp: ftp)
            for watts in range {
                #expect(PowerZone.zone(forPower: watts, ftp: ftp) == zone, "\(watts)W in \(zone.displayName).wattRange but classifies into \(String(describing: PowerZone.zone(forPower: watts, ftp: ftp)))")
            }
        }
    }

    @Test
    func zoneForPowerBoundaryConditions() {
        let ftp = 200

        // Zone 1: up to 55% = 110W
        #expect(PowerZone.zone(forPower: 0, ftp: ftp) == .zone1)
        #expect(PowerZone.zone(forPower: 110, ftp: ftp) == .zone1)

        // Zone 2: 55.1-75%
        #expect(PowerZone.zone(forPower: 111, ftp: ftp) == .zone2)
        #expect(PowerZone.zone(forPower: 150, ftp: ftp) == .zone2)

        // Zone 3: 76-90%
        #expect(PowerZone.zone(forPower: 151, ftp: ftp) == .zone3)
        #expect(PowerZone.zone(forPower: 180, ftp: ftp) == .zone3)

        // Zone 4: 91-105%
        #expect(PowerZone.zone(forPower: 200, ftp: ftp) == .zone4)
        #expect(PowerZone.zone(forPower: 210, ftp: ftp) == .zone4)

        // Zone 5: 106-120%
        #expect(PowerZone.zone(forPower: 220, ftp: ftp) == .zone5)
        #expect(PowerZone.zone(forPower: 240, ftp: ftp) == .zone5)

        // Zone 6: 121-150%
        #expect(PowerZone.zone(forPower: 250, ftp: ftp) == .zone6)
        #expect(PowerZone.zone(forPower: 300, ftp: ftp) == .zone6)

        // Zone 7: >150%
        #expect(PowerZone.zone(forPower: 301, ftp: ftp) == .zone7)
        #expect(PowerZone.zone(forPower: 500, ftp: ftp) == .zone7)
    }

    @Test
    func zoneForPowerInvalidInputs() {
        #expect(PowerZone.zone(forPower: 100, ftp: 0) == nil)
        #expect(PowerZone.zone(forPower: -1, ftp: 200) == nil)
    }

    @Test
    func containsPower() {
        #expect(PowerZone.zone4.contains(power: 200, ftp: 200) == true)
        #expect(PowerZone.zone4.contains(power: 100, ftp: 200) == false)
    }

    @Test
    func rangeDescriptionFormats() {
        let ftp = 200
        #expect(PowerZone.zone1.rangeDescription(ftp: ftp).contains("<"))
        #expect(PowerZone.zone7.rangeDescription(ftp: ftp).contains(">"))
        #expect(PowerZone.zone4.rangeDescription(ftp: ftp).contains("-"))
        #expect(PowerZone.zone4.rangeDescription(ftp: ftp).hasSuffix("W"))
    }
}
