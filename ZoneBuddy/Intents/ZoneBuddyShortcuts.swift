import AppIntents

struct ZoneBuddyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start a workout in \(.applicationName)",
                "Start \(\.$workout) in \(.applicationName)",
                "Begin my \(\.$workout) ride in \(.applicationName)"
            ],
            shortTitle: "Start Workout",
            systemImageName: "play.fill"
        )
        
        AppShortcut(
            intent: GetCurrentIntervalIntent(),
            phrases: [
                "What's my current interval in \(.applicationName)",
                "Show my current \(.applicationName) interval"
            ],
            shortTitle: "Current Interval",
            systemImageName: "info.circle"
        )
        
        AppShortcut(
            intent: GetNextIntervalIntent(),
            phrases: [
                "What's my next interval in \(.applicationName)",
                "Show my next \(.applicationName) interval"
            ],
            shortTitle: "Next Interval",
            systemImageName: "arrow.right.circle"
        )
    }
}
