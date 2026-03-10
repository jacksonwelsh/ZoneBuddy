import SwiftUI
import SwiftData

@Observable
final class WorkoutEditorViewModel {
    var workout: Workout
    var workoutName: String
    var transitionWarningDuration: Int
    var intervals: [Interval]
    var playlistID: String?
    var playlistName: String?
    var playlistKind: String?
    var playlistShuffle: Bool
    var playlistRepeat: Bool
    var playlistAutoMix: Bool

    private let modelContext: ModelContext

    init(workout: Workout, modelContext: ModelContext) {
        self.workout = workout
        self.workoutName = workout.name
        self.transitionWarningDuration = workout.transitionWarningDuration
        self.intervals = workout.sortedIntervals
        self.playlistID = workout.playlistID
        self.playlistName = workout.playlistName
        self.playlistKind = workout.playlistKind
        self.playlistShuffle = workout.playlistShuffle
        self.playlistRepeat = workout.playlistRepeat
        self.playlistAutoMix = workout.playlistAutoMix
        self.modelContext = modelContext
    }

    func addInterval(zone: PowerZone?, duration: Int) {
        let interval = Interval(
            zone: zone,
            duration: duration,
            sortOrder: intervals.count
        )
        interval.workout = workout
        modelContext.insert(interval)
        intervals.append(interval)
        saveChanges()
    }

    func addWarmup(duration: Int) {
        addInterval(zone: nil, duration: duration)
    }

    func removeInterval(at offsets: IndexSet) {
        let toDelete = offsets.map { intervals[$0] }
        for interval in toDelete {
            modelContext.delete(interval)
        }
        intervals.remove(atOffsets: offsets)
        reindex()
        saveChanges()
    }

    func moveInterval(from source: IndexSet, to destination: Int) {
        intervals.move(fromOffsets: source, toOffset: destination)
        reindex()
        saveChanges()
    }

    func selectPlaylist(id: String, name: String, kind: MusicPickerKind) {
        playlistID = id
        playlistName = name
        playlistKind = kind.rawValue
        updateWorkoutSettings()
    }

    func clearPlaylist() {
        playlistID = nil
        playlistName = nil
        playlistKind = nil
        playlistShuffle = false
        playlistRepeat = false
        playlistAutoMix = false
        updateWorkoutSettings()
    }

    func updateWorkoutSettings() {
        workout.name = workoutName
        workout.transitionWarningDuration = transitionWarningDuration
        workout.playlistID = playlistID
        workout.playlistName = playlistName
        workout.playlistKind = playlistKind
        workout.playlistShuffle = playlistShuffle
        workout.playlistRepeat = playlistRepeat
        workout.playlistAutoMix = playlistAutoMix
        saveChanges()
    }

    func updateName() {
        updateWorkoutSettings()
    }

    func updateInterval(_ interval: Interval, zone: PowerZone?, duration: Int) {
        interval.zone = zone
        interval.duration = duration
        saveChanges()
    }

    func isCooldown(_ interval: Interval) -> Bool {
        guard let last = intervals.last else { return false }
        return last.persistentModelID == interval.persistentModelID
            && interval.zone == .zone1
    }

    var totalDuration: Int {
        intervals.reduce(0) { $0 + $1.duration }
    }

    var isPlayable: Bool {
        !intervals.isEmpty
    }

    private func reindex() {
        for (index, interval) in intervals.enumerated() {
            interval.sortOrder = index
        }
    }

    private func saveChanges() {
        try? modelContext.save()
    }
}
