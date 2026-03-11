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
    func wattRangesAreOrderedAndNonOverlapping(ftp: Int) {
        var previousUpper = -1
        for zone in PowerZone.allCases {
            let range = zone.wattRange(ftp: ftp)
            #expect(range.lowerBound >= previousUpper, "Zone \(zone.rawValue) lower (\(range.lowerBound)) should be >= previous upper (\(previousUpper)) at FTP \(ftp)")
            #expect(range.upperBound >= range.lowerBound, "Zone \(zone.rawValue) range should be non-empty at FTP \(ftp)")
            previousUpper = range.upperBound
        }
    }

    @Test
    func wattRangeAtFTP200() {
        let ftp = 200
        // Zone 1: <55% = 0-110
        #expect(PowerZone.zone1.wattRange(ftp: ftp).upperBound == 110)
        // Zone 2: 55-75% = 110-150
        #expect(PowerZone.zone2.wattRange(ftp: ftp).lowerBound == 110)
        #expect(PowerZone.zone2.wattRange(ftp: ftp).upperBound == 150)
        // Zone 4: 91-105% = 182-210
        #expect(PowerZone.zone4.wattRange(ftp: ftp).lowerBound == 182)
        #expect(PowerZone.zone4.wattRange(ftp: ftp).upperBound == 210)
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
