import AppIntents
import Foundation
import SwiftData

struct WorkoutEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workout"
    static var defaultQuery = WorkoutQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WorkoutQuery: EntityQuery {
    func entities(for identifiers: [WorkoutEntity.ID]) async throws -> [WorkoutEntity] {
        await MainActor.run {
            identifiers.compactMap { id in
                DataStore.shared.fetchWorkout(id: id).map { WorkoutEntity(id: $0.id, name: $0.name) }
            }
        }
    }

    func suggestedEntities() async throws -> [WorkoutEntity] {
        await MainActor.run {
            DataStore.shared.fetchWorkouts().map { WorkoutEntity(id: $0.id, name: $0.name) }
        }
    }
}

extension WorkoutQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [WorkoutEntity] {
        await MainActor.run {
            DataStore.shared.fetchWorkouts().map { WorkoutEntity(id: $0.id, name: $0.name) }
        }
    }
}
