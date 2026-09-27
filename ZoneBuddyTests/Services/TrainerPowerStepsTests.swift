import Testing
@testable import ZoneBuddy

struct TrainerPowerStepsTests {
    @Test(arguments: [181, 182, 183, 184])
    func unevenTargetsUseAdjacentGridValues(watts: Int) {
        #expect(TrainerPowerSteps.adjacent(to: watts, increasing: false) == 180)
        #expect(TrainerPowerSteps.adjacent(to: watts, increasing: true) == 185)
    }

    @Test
    func alignedTargetsMoveByFiveWatts() {
        #expect(TrainerPowerSteps.adjacent(to: 180, increasing: false) == 175)
        #expect(TrainerPowerSteps.adjacent(to: 180, increasing: true) == 185)
    }

    @Test
    func draggingPreservesStartAndVisitsEachAdjacentTick() {
        let range = 50...1000
        #expect(TrainerPowerSteps.target(start: 183, steps: 0, range: range) == 183)
        #expect(TrainerPowerSteps.target(start: 183, steps: -1, range: range) == 180)
        #expect(TrainerPowerSteps.target(start: 183, steps: 1, range: range) == 185)
        #expect(TrainerPowerSteps.target(start: 183, steps: -2, range: range) == 175)
        #expect(TrainerPowerSteps.target(start: 183, steps: 2, range: range) == 190)
    }

    @Test
    func supportedRangeClampsEvenWithUnevenEndpoints() {
        #expect(TrainerPowerSteps.target(start: 53, steps: -1, range: 53...998) == 53)
        #expect(TrainerPowerSteps.target(start: 998, steps: 1, range: 53...998) == 998)
        #expect(TrainerPowerSteps.target(start: 53, steps: 1, range: 53...998) == 55)
        #expect(TrainerPowerSteps.target(start: 998, steps: -1, range: 53...998) == 995)
        #expect(TrainerPowerSteps.target(start: 183, steps: -100, range: 53...998) == 53)
        #expect(TrainerPowerSteps.target(start: 183, steps: 1000, range: 53...998) == 998)
    }
}
