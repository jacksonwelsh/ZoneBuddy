import Testing
import Foundation
@testable import ZoneBuddy

@MainActor
struct FTPRampTestProtocolTests {
    @Test
    func intervalsHaveWarmupRampStepsAndCooldown() {
        let intervals = FTPRampTestProtocol.makeIntervals()

        let warmup = intervals.first
        #expect(warmup?.zone == nil)
        #expect(warmup?.targetWatts == nil)
        #expect(warmup?.duration == FTPRampTestProtocol.warmupDuration)

        let cooldown = intervals.last
        #expect(cooldown?.targetWatts == nil)
        #expect(cooldown?.duration == FTPRampTestProtocol.cooldownDuration)
    }

    @Test
    func rampStepsIncreaseMonotonicallyByConfiguredStep() {
        let intervals = FTPRampTestProtocol.makeIntervals()
        let rampSteps = intervals.dropFirst().dropLast()

        let targets = rampSteps.compactMap(\.targetWatts)
        #expect(targets.count == FTPRampTestProtocol.rampStepCount)
        #expect(targets.first == FTPRampTestProtocol.rampStartWatts)
        #expect(targets.last == FTPRampTestProtocol.rampMaxWatts)

        for (idx, watts) in targets.enumerated() where idx > 0 {
            #expect(watts - targets[idx - 1] == FTPRampTestProtocol.rampStepWatts)
        }
    }

    @Test
    func rampStepsAreOneMinuteEach() {
        let intervals = FTPRampTestProtocol.makeIntervals()
        let rampSteps = intervals.dropFirst().dropLast()
        for step in rampSteps {
            #expect(step.duration == FTPRampTestProtocol.stepDuration)
        }
    }

    @Test
    func bestMinutePowerFindsHighestRollingAverage() {
        // 60 samples at 200W, then 60 samples at 300W (the peak), then 60 at 250W.
        let lowPhase = Array(repeating: 200, count: 60)
        let peakPhase = Array(repeating: 300, count: 60)
        let taperPhase = Array(repeating: 250, count: 60)
        let samples = lowPhase + peakPhase + taperPhase

        let best = FTPRampTestProtocol.bestMinutePower(fromSamplePowers: samples)
        #expect(best == 300)
    }

    @Test
    func bestMinutePowerHandlesRampingStream() {
        // Linear ramp 100..300W over 200 samples. Best 1-min window is the last 60.
        let samples = (0..<200).map { 100 + ($0 * 200 / 199) }
        let best = FTPRampTestProtocol.bestMinutePower(fromSamplePowers: samples)
        let expected = Int((Double(samples.suffix(60).reduce(0, +)) / 60.0).rounded())
        #expect(best == expected)
    }

    @Test
    func bestMinutePowerReturnsNilForUndersizedStream() {
        let samples = Array(repeating: 250, count: 59)
        #expect(FTPRampTestProtocol.bestMinutePower(fromSamplePowers: samples) == nil)
    }

    @Test
    func computeFTPApplies75PercentToBestMinute() {
        let samples = Array(repeating: 400, count: 120)
        let ftp = FTPRampTestProtocol.computeFTP(fromSamplePowers: samples)
        #expect(ftp == 300) // 400 * 0.75
    }

    @Test
    func phaseLabelsWarmupRampAndCooldown() {
        #expect(FTPRampTestProtocol.phaseLabel(forIndex: 0) == "Warmup")
        #expect(FTPRampTestProtocol.phaseLabel(forIndex: FTPRampTestProtocol.firstRampIntervalIndex) == "Ramp Step 1")
        #expect(FTPRampTestProtocol.phaseLabel(forIndex: FTPRampTestProtocol.cooldownIntervalIndex) == "Cooldown")
    }
}
