import FoundationModels

@Generable
struct GeneratedInterval {
    @Guide(description: "Power zone 1-7, or null for warmup/cooldown")
    var zone: Int?

    @Guide(description: "Duration in seconds, typically 30-600")
    var duration: Int
}

@Generable
struct GeneratedWorkout {
    @Guide(description: "A short descriptive name for this workout")
    var name: String

    @Guide(description: "Ordered list of intervals")
    var intervals: [GeneratedInterval]
}
