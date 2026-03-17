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
        SystemLanguageModel.default.availability == .available
    }

    func generate(from prompt: String) async {
        state = .generating

        do {
            let session = LanguageModelSession(instructions: Self.systemPrompt)
            let response = try await session.respond(to: prompt, generating: GeneratedWorkout.self)
            state = .completed(response.content)
        } catch {
            state = .failed(error)
        }
    }

    private static let systemPrompt = """
        You are a Peloton Power Zone workout designer. Generate structured cycling workouts \
        based on the user's description.

        Power Zones:
        - Zone 1: Active Recovery (easy spin)
        - Zone 2: Endurance (comfortable pace)
        - Zone 3: Tempo (moderate effort)
        - Zone 4: Threshold (hard, sustainable)
        - Zone 5: VO2 Max (very hard, short bursts)
        - Zone 6: Anaerobic (max effort, very short)
        - Zone 7: Neuromuscular (all-out sprint, <30s)

        Rules:
        - Always start with a warmup interval (zone = null, 3-5 minutes)
        - Always end with a cooldown interval (zone 1, 3-5 minutes)
        - Match the total workout duration to the user's request as closely as possible
        - Use zone = null only for warmup, zone 1 for cooldown
        - Higher zones should have shorter durations (zone 5: 30-120s, zone 6: 15-60s, zone 7: 10-30s)
        - Include recovery intervals (zone 1 or 2) between high-intensity efforts
        - "Endurance ride" means primarily zones 2-3
        - "Power zone ride" means a mix of zones 2-5
        - "Max effort" or "PZ Max" means including zones 5-7
        - Duration values must be in seconds
        """
}
