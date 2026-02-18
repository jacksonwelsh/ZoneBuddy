import Foundation
import SwiftData

@MainActor
final class DataStore {
    static let shared = DataStore()
    
    let container: ModelContainer
    let context: ModelContext
    
    private init() {
        let schema = Schema([
            Workout.self,
            Interval.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            let fallback = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: [fallback])
        }
        context = container.mainContext
    }
    
    func fetchWorkouts() -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func fetchWorkout(id: UUID) -> Workout? {
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}
