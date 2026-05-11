import FoundationModels
import Observation

@Observable
final class WorkoutGenerationService {
    enum GenerationState {
        case idle
        case generating
        case completed(GeneratedWorkout)
        case failed(Error)
    }

    var state: GenerationState = .idle

    static var isAvailable: Bool {
        #if DEBUG
        return SystemLanguageModel.default.availability == .available
        #else
        return false
        #endif
    }

    private static let maxRepairAttempts = 2
    private static let durationToleranceFraction = 0.05

    func generate(from prompt: String) async {
        state = .generating

        do {
            let session = LanguageModelSession(instructions: Self.systemPrompt)
            let options = GenerationOptions(temperature: 0.3)

            var workout = try await session.respond(
                to: prompt,
                generating: GeneratedWorkout.self,
                options: options
            ).content

            for _ in 0..<Self.maxRepairAttempts {
                let actual = workout.intervals.reduce(0) { $0 + $1.duration }
                let target = workout.targetDurationSeconds
                guard target > 0 else { break }
                let tolerance = max(30, Int(Double(target) * Self.durationToleranceFraction))
                if abs(actual - target) <= tolerance { break }

                let repairPrompt = """
                    The intervals you generated sum to \(actual) seconds, but the target is \
                    \(target) seconds (off by \(actual - target)). Regenerate the workout so \
                    the intervals sum exactly to \(target) seconds. Keep the same workout \
                    style and zone distribution, and set actualDurationSeconds to \(target).
                    """
                workout = try await session.respond(
                    to: repairPrompt,
                    generating: GeneratedWorkout.self,
                    options: options
                ).content
            }

            state = .completed(workout)
        } catch {
            state = .failed(error)
        }
    }

    private static let systemPrompt = """
        You are a Peloton Power Zone workout designer. Generate structured cycling workouts \
        based on the user's description.

        BEFORE RESPONDING, you MUST:
        1. Read the user prompt and extract the target total duration in seconds. Set \
        targetDurationSeconds to that value. If the user says "45 minute", that is 2700 seconds.
        2. Plan intervals whose durations sum EXACTLY to targetDurationSeconds.
        3. Add up every interval.duration. Set actualDurationSeconds to that sum. \
        actualDurationSeconds MUST equal targetDurationSeconds.

        All duration values are in SECONDS. Minutes are not seconds. 5 minutes = 300, \
        10 minutes = 600, 1 minute = 60, 90 seconds = 90.

        Power Zones:
        - Zone 1: Active Recovery (easy spin)
        - Zone 2: Endurance (comfortable pace)
        - Zone 3: Tempo (moderate effort)
        - Zone 4: Threshold (hard, sustainable)
        - Zone 5: VO2 Max (very hard, short bursts)
        - Zone 6: Anaerobic (max effort, very short)
        - Zone 7: Neuromuscular (all-out sprint, <30s)

        Rules:
        - ALWAYS start with a warmup interval (zone = null), typically 300-600 seconds.
        - ALWAYS end with a cooldown interval (zone 1), typically 60-180 seconds.
        - Use zone = null ONLY for the opening warmup. Use zone 1 for cooldown and active recovery.
        - Include recovery intervals (zone 1 or 2) between high-intensity efforts.
        - "Endurance ride" = primarily zones 2-3.
        - "Power zone ride" = mix of zones 2-5.
        - "Max effort" or "PZ Max" = include zones 5-7.
        - Follow the user's prompt closely. If they specify exact durations or patterns, \
        reproduce them exactly.

        EXAMPLE — Prompt: "45-minute endurance ride with alternating Zone 2 and Zone 3"
        targetDurationSeconds: 2700
        Intervals (sum = 2700):
        - zone: null, duration: 600   (warmup)
        - zone: 2,    duration: 180
        - zone: 3,    duration: 480
        - zone: 2,    duration: 180
        - zone: 3,    duration: 480
        - zone: 2,    duration: 180
        - zone: 3,    duration: 480
        - zone: 1,    duration: 120   (cooldown)
        actualDurationSeconds: 2700
        """
}
