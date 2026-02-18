import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Defaults") {
                    HStack {
                        Label("Warning Interval", systemImage: "timer")
                        Spacer()
                        Stepper(
                            "\(settings.transitionWarningDuration)s",
                            value: $settings.transitionWarningDuration,
                            in: 3...30
                        )
                        .fixedSize()
                    }

                    Toggle(isOn: $settings.audioCuesEnabled) {
                        Label("Audio Cues", systemImage: "speaker.wave.2.fill")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(.systemGroupedBackground))
            .scrollContentBackground(.visible)
            .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    SettingsView()
}

#Preview("In Sheet") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SettingsView()
        }
}
