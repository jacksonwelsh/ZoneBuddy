import Testing
@testable import ZoneBuddy

@MainActor
struct IntervalTests {
    @Test
    func warmupInterval() {
        let interval = Interval.warmup(duration: 300, sortOrder: 0)
        #expect(interval.isWarmup == true)
        #expect(interval.zone == nil)
        #expect(interval.duration == 300)
    }

    @Test
    func zoneInterval() {
        let interval = Interval(zone: .zone5, duration: 120, sortOrder: 0)
        #expect(interval.isWarmup == false)
        #expect(interval.zone == .zone5)
        #expect(interval.zoneRawValue == 5)
    }

    @Test
    func zoneRoundTrip() {
        let interval = Interval(zone: .zone3, duration: 60, sortOrder: 0)
        #expect(interval.zone == .zone3)

        interval.zone = .zone7
        #expect(interval.zone == .zone7)
        #expect(interval.zoneRawValue == 7)

        interval.zone = nil
        #expect(interval.isWarmup == true)
    }

    @Test
    func sortOrderIsStored() {
        let interval = Interval(zone: .zone2, duration: 60, sortOrder: 5)
        #expect(interval.sortOrder == 5)
    }
}
