import SwiftUI

struct WatchSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = SettingsManager.shared
        NavigationStack {
            Form {
                Section("Audio") {
                    Toggle("Audio Cues", isOn: $settings.audioCuesEnabled)
                }
                Section("Transitions") {
                    Stepper(
                        "Warning: \(settings.transitionWarningDuration)s",
                        value: $settings.transitionWarningDuration,
                        in: 3...30
                    )
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
