import FoundationModels

@Generable
struct GeneratedInterval {
    @Guide(description: "Power zone 1-7, or null for warmup/cooldown")
    var zone: Int?

    @Guide(description: "Duration in seconds. Convert minutes to seconds (1 min = 60 sec).", .range(15...1800))
    var duration: Int
}

@Generable
struct GeneratedWorkout {
    @Guide(description: "A short descriptive name for this workout")
    var name: String

    @Guide(description: "The user's requested total workout duration in seconds. Extract from the prompt (e.g. '45 minute' = 2700). If unspecified, pick a reasonable total and use it consistently.")
    var targetDurationSeconds: Int

    @Guide(description: "The arithmetic sum of every interval.duration in this workout. MUST equal targetDurationSeconds.")
    var actualDurationSeconds: Int

    @Guide(description: "Ordered list of intervals. First is warmup (zone null), last is cooldown (zone 1).")
    var intervals: [GeneratedInterval]
}
