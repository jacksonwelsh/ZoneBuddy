import AppIntents
import SwiftUI

struct GetNextIntervalIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Next Interval"
    static var description = IntentDescription("Tells you what the next interval is in your current workout.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let viewModel = WorkoutSessionManager.shared.activeViewModel else {
            return .result(value: "No active workout", dialog: "You don't have an active workout right now.")
        }
        
        if let next = viewModel.nextInterval {
            let label = viewModel.upcomingLabel
            let duration = next.duration.formattedDuration
            return .result(value: "\(label) for \(duration)", dialog: "Your next interval is \(label) for \(duration).")
        } else {
            return .result(value: "This is the last interval", dialog: "You're on your last interval!")
        }
    }
}
