import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = SettingsManager.shared
    var bikeManager: BikeConnecting = LiveBikeConnectionManager.shared
    @State private var ftpText: String = ""
    @State private var maxHRText: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        BikeConnectionView(bikeManager: bikeManager)
                    } label: {
                        HStack {
                            Label("Bike Connection", systemImage: "bicycle")
                            Spacer()
                            Text(bikeManager.isConnected ? (bikeManager.connectedBikeName ?? "Connected") : "Not Connected")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $settings.promptForBikeBeforeWorkout) {
                        Label("Prompt Before Workout", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } header: {
                    Text("Bike")
                } footer: {
                    Text("When enabled, you'll be asked to connect a bike before starting each workout if one isn't already connected.")
                }

                Section {
                    HStack {
                        Label("FTP", systemImage: "bolt.fill")
                        Spacer()
                        TextField("200", text: $ftpText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: ftpText) { _, newValue in
                                if let value = Int(newValue), (50...500).contains(value) {
                                    settings.functionalThresholdPower = value
                                }
                            }
                        Text("W")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Max HR", systemImage: "heart.fill")
                        Spacer()
                        TextField("190", text: $maxHRText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: maxHRText) { _, newValue in
                                if let value = Int(newValue), (100...230).contains(value) {
                                    settings.maxHeartRate = value
                                }
                            }
                        Text("bpm")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Training")
                } footer: {
                    Text("FTP is used for power zone ranges (50–500W). Max HR is used for heart rate zone ranges (100–230 bpm).")
                }

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

                Section("Music") {
                    Toggle(isOn: $settings.playlistTakesOverMusic) {
                        Label("Playlist Replaces Current Music", systemImage: "music.note.list")
                    }
                }

                Section("Workout Display") {
                    NavigationLink {
                        WorkoutLayoutEditorView()
                    } label: {
                        Label("Customize Tiles", systemImage: "square.grid.2x2")
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
            .onAppear {
                ftpText = "\(settings.functionalThresholdPower)"
                maxHRText = "\(settings.maxHeartRate)"
            }
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
