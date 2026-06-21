import SwiftUI

struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared
    var bikeManager: any BikeConnecting = BikeManagerProvider.current
    @State private var ftpText: String = ""
    @State private var maxHRText: String = ""
    @State private var weightText: String = ""
    @State private var weightSyncStatus: WeightSyncStatus = .idle
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case ftp, maxHR, weight
    }

    private enum WeightSyncStatus: Equatable {
        case idle
        case syncing
        case synced(kg: Double)
        case failed(String)
    }

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
                            .focused($focusedField, equals: .ftp)
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
                            .focused($focusedField, equals: .maxHR)
                            .onChange(of: maxHRText) { _, newValue in
                                if let value = Int(newValue), (100...230).contains(value) {
                                    settings.maxHeartRate = value
                                }
                            }
                        Text("bpm")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        FTPTestIntroView(bikeManager: bikeManager)
                    } label: {
                        Label("Take FTP Test", systemImage: "stopwatch")
                    }
                } header: {
                    Text("Training")
                } footer: {
                    Text("Take an FTP test to measure your threshold power, or enter it manually above. Max HR is used for heart rate zone ranges (100–230 bpm).")
                }

                Section {
                    HStack {
                        Label("Weight", systemImage: "scalemass.fill")
                        Spacer()
                        TextField("75", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .weight)
                            .onChange(of: weightText) { _, newValue in
                                if let value = Double(newValue), (30...250).contains(value) {
                                    settings.riderWeightKg = value
                                }
                            }
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await syncWeightFromHealth() }
                    } label: {
                        HStack {
                            Label(syncButtonLabel, systemImage: syncButtonIcon)
                            if weightSyncStatus == .syncing {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(weightSyncStatus == .syncing)
                } header: {
                    Text("Rider")
                } footer: {
                    Text("Used by Route Ride to compute virtual speed from your power and the road grade. Heavier riders climb slower and descend faster.")
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

                #if DEBUG
                SimulatorDebugView()
                #endif
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .scrollContentBackground(.visible)
            .safeAreaInset(edge: .bottom) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button {
                            focusedField = nil
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.blue, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                    }
                }
            }
            .onAppear {
                ftpText = "\(settings.functionalThresholdPower)"
                maxHRText = "\(settings.maxHeartRate)"
                weightText = formattedWeight(settings.riderWeightKg)
            }
        }
    }

    private var syncButtonLabel: String {
        switch weightSyncStatus {
        case .idle:            return "Sync from Apple Health"
        case .syncing:         return "Syncing…"
        case .synced(let kg):  return "Synced (\(formattedWeight(kg)) kg)"
        case .failed(let msg): return "Sync failed: \(msg)"
        }
    }

    private var syncButtonIcon: String {
        switch weightSyncStatus {
        case .synced:  return "checkmark.circle.fill"
        case .failed:  return "exclamationmark.triangle.fill"
        default:       return "heart.text.square.fill"
        }
    }

    private func syncWeightFromHealth() async {
        weightSyncStatus = .syncing
        if let kg = await BodyMassSync.latestBodyMassKg() {
            settings.riderWeightKg = kg
            weightText = formattedWeight(kg)
            weightSyncStatus = .synced(kg: kg)
        } else {
            weightSyncStatus = .failed("no body-mass sample in Health")
        }
    }

    private func formattedWeight(_ kg: Double) -> String {
        String(format: "%.1f", kg)
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
