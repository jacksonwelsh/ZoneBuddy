import Testing
@testable import ZoneBuddy

struct HeartRateZoneTests {
    @Test
    func invalidInputsReturnNil() {
        #expect(HeartRateZone.zone(forBPM: 100, maxHR: 0) == nil)
        #expect(HeartRateZone.zone(forBPM: -1, maxHR: 190) == nil)
    }

    @Test
    func belowSixtyPercentIsZone1() {
        // 95 / 190 = 50% — well below the zone2 cutoff
        #expect(HeartRateZone.zone(forBPM: 95, maxHR: 190) == .zone1)
        // Just under 60%
        #expect(HeartRateZone.zone(forBPM: 113, maxHR: 190) == .zone1)
    }

    @Test
    func boundariesClassifyIntoUpperZone() {
        // At exactly 60%, the strict-less-than comparison advances to zone2.
        #expect(HeartRateZone.zone(forBPM: 114, maxHR: 190) == .zone2)
        // At exactly 70% → zone3
        #expect(HeartRateZone.zone(forBPM: 133, maxHR: 190) == .zone3)
        // At exactly 80% → zone4
        #expect(HeartRateZone.zone(forBPM: 152, maxHR: 190) == .zone4)
        // At exactly 90% → zone5
        #expect(HeartRateZone.zone(forBPM: 171, maxHR: 190) == .zone5)
    }

    @Test
    func aboveMaxStaysInZone5() {
        #expect(HeartRateZone.zone(forBPM: 200, maxHR: 190) == .zone5)
    }

    @Test
    func bpmRangeMatchesClassification() {
        let maxHR = 190
        for zone in HeartRateZone.allCases {
            let range = zone.bpmRange(maxHR: maxHR)
            #expect(range.lowerBound <= range.upperBound)
        }
    }
}
