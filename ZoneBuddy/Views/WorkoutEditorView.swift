import SwiftUI
import SwiftData

struct WorkoutEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WorkoutEditorViewModel
    @State private var showingAddInterval = false
    @State private var editingInterval: Interval?
    @State private var selectedZone: PowerZone? = .zone3
    @State private var durationMinutes: Int = 5
    @State private var durationSeconds: Int = 0
    @State private var navigateToPlayer = false
    @State private var showingPlaylistPicker = false
    @FocusState private var nameFieldFocused: Bool

    let isNew: Bool

    init(workout: Workout, isNew: Bool = false) {
        self.isNew = isNew
        _viewModel = State(initialValue: WorkoutEditorViewModel(
            workout: workout,
            modelContext: workout.modelContext!
        ))
    }

    var body: some View {
        List {
            Section("Workout Name") {
                TextField("Workout Name", text: $viewModel.workoutName)
                    .focused($nameFieldFocused)
                    .onSubmit { viewModel.updateName() }
            }

            Section {
                if viewModel.intervals.isEmpty {
                    ContentUnavailableView(
                        "No Intervals",
                        systemImage: "figure.indoor.cycle",
                        description: Text("Add intervals to build your workout.")
                    )
                } else {
                    ForEach(Array(viewModel.intervals.enumerated()), id: \.element.persistentModelID) { _, interval in
                        IntervalRowView(
                            interval: interval,
                            isCooldown: viewModel.isCooldown(interval)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingInterval = interval
                            selectedZone = interval.zone
                            durationMinutes = interval.duration / 60
                            durationSeconds = interval.duration % 60
                        }
                    }
                    .onDelete { viewModel.removeInterval(at: $0) }
                    .onMove { viewModel.moveInterval(from: $0, to: $1) }
                }
            } header: {
                HStack {
                    Text("Intervals")
                    Spacer()
                    Text(viewModel.totalDuration.formattedDuration)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Music") {
                Button {
                    showingPlaylistPicker = true
                } label: {
                    HStack {
                        Label(
                            viewModel.playlistName ?? "Choose Music",
                            systemImage: "music.note.list"
                        )
                        Spacer()
                        if viewModel.playlistID != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                if viewModel.playlistID != nil {
                    Toggle("Shuffle", isOn: $viewModel.playlistShuffle)
                    Toggle("Repeat", isOn: $viewModel.playlistRepeat)
                    Toggle("Auto Mix", isOn: $viewModel.playlistAutoMix)
                }
            }

            Section("Settings") {
                Stepper(value: $viewModel.transitionWarningDuration, in: 0...30) {
                    HStack {
                        Text("Transition Warning")
                        Spacer()
                        Text("\(viewModel.transitionWarningDuration)s")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Edit Workout")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") {
                    editingInterval = nil
                    selectedZone = .zone3
                    durationMinutes = 5
                    durationSeconds = 0
                    showingAddInterval = true
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigateToPlayer = true
                } label: {
                    Label("Start Ride", systemImage: "play.fill")
                }
                .disabled(!viewModel.isPlayable)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareWorkoutButton(workout: viewModel.workout)
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .navigationDestination(isPresented: $navigateToPlayer) {
            WorkoutPlayerView(
                intervals: viewModel.intervals,
                workoutName: viewModel.workoutName,
                transitionWarningDuration: viewModel.transitionWarningDuration,
                playlistID: viewModel.playlistID,
                playlistKind: viewModel.playlistKind,
                playlistShuffle: viewModel.playlistShuffle,
                playlistRepeat: viewModel.playlistRepeat,
                playlistAutoMix: viewModel.playlistAutoMix
            )
        }
        .sheet(isPresented: $showingAddInterval) {
            intervalSheet(editing: nil)
        }
        .sheet(item: $editingInterval) { interval in
            intervalSheet(editing: interval)
        }
        .sheet(isPresented: $showingPlaylistPicker) {
            PlaylistPickerView(
                selectedPlaylistID: viewModel.playlistID,
                onSelect: { id, name, kind in
                    viewModel.selectPlaylist(id: id, name: name, kind: kind)
                },
                onRemove: {
                    viewModel.clearPlaylist()
                }
            )
        }
        .onAppear {
            if isNew {
                nameFieldFocused = true
            }
        }
        .onDisappear {
            viewModel.updateWorkoutSettings()
        }
    }

    private func intervalSheet(editing interval: Interval?) -> some View {
        let isEditing = interval != nil
        return NavigationStack {
            Form {
                Picker("Zone", selection: $selectedZone) {
                    HStack {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 20, height: 20)
                        Text("Warmup")
                    }
                    .tag(nil as PowerZone?)

                    ForEach(PowerZone.allCases) { zone in
                        HStack {
                            Circle()
                                .fill(zone.color)
                                .frame(width: 20, height: 20)
                            Text(zone.zoneName)
                        }
                        .tag(zone as PowerZone?)
                    }
                }

                HStack {
                    Picker("Minutes", selection: $durationMinutes) {
                        ForEach(0..<60) { Text("\($0) min").tag($0) }
                    }
                    Picker("Seconds", selection: $durationSeconds) {
                        ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) {
                            Text("\($0) sec").tag($0)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Interval" : "Add Interval")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddInterval = false
                        editingInterval = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        let totalSeconds = durationMinutes * 60 + durationSeconds
                        guard totalSeconds > 0 else { return }
                        let zone: PowerZone? = selectedZone

                        if let interval {
                            viewModel.updateInterval(interval, zone: zone, duration: totalSeconds)
                        } else {
                            viewModel.addInterval(zone: zone, duration: totalSeconds)
                        }
                        showingAddInterval = false
                        editingInterval = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    let container = try! ModelContainer(for: Workout.self, Interval.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let workout = Workout(name: "PZ Endurance", intervals: [
        Interval.warmup(duration: 300, sortOrder: 0),
        Interval(zone: .zone2, duration: 300, sortOrder: 1),
        Interval(zone: .zone3, duration: 180, sortOrder: 2),
        Interval(zone: .zone1, duration: 300, sortOrder: 3),
    ])
    context.insert(workout)
    return NavigationStack {
        WorkoutEditorView(workout: workout)
    }
    .modelContainer(container)
}
