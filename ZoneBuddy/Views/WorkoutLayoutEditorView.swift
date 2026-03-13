import SwiftUI

struct WorkoutLayoutEditorView: View {
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        List {
            Section("Metrics") {
                Toggle("Power", isOn: $settings.layoutPreferences.showPower)
                Toggle("Cadence", isOn: $settings.layoutPreferences.showCadence)
                Toggle("Heart Rate", isOn: $settings.layoutPreferences.showHeartRate)
                Toggle("Speed", isOn: $settings.layoutPreferences.showSpeed)
                Toggle("Distance", isOn: $settings.layoutPreferences.showDistance)
                Toggle("Calories", isOn: $settings.layoutPreferences.showCalories)
                Toggle("Average Power", isOn: $settings.layoutPreferences.showAvgPower)
                Toggle("Total Output", isOn: $settings.layoutPreferences.showOutput)
            }

            Section("Display") {
                Toggle("Zone Info", isOn: $settings.layoutPreferences.showZoneInfo)
                Toggle("Power Zone Bar", isOn: $settings.layoutPreferences.showPowerBar)
                Toggle("Heart Rate Zone Bar", isOn: $settings.layoutPreferences.showHeartRateBar)
            }

            Section {
                Toggle("Music Controls", isOn: $settings.layoutPreferences.showMusicControls)
            } header: {
                Text("Controls")
            } footer: {
                Text("Hidden tiles won't appear during workouts.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Workout Display")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
    }
}
