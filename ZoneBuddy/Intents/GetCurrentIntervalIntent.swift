import AppIntents
import SwiftUI

struct GetCurrentIntervalIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Current Interval"
    static var description = IntentDescription("Tells you what your current interval is.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let viewModel = WorkoutSessionManager.shared.activeViewModel else {
            return .result(value: "No active workout", dialog: "You don't have an active workout right now.")
        }
        
        let label = viewModel.currentLabel
        let remaining = viewModel.secondsRemaining.formattedDuration
        return .result(value: "\(label), \(remaining) remaining", dialog: "You are currently in \(label) with \(remaining) remaining.")
    }
}
