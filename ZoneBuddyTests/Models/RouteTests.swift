import Testing
import Foundation
import SwiftData
@testable import ZoneBuddy

@MainActor
struct RouteTests {

    /// Retain the container so SwiftData doesn't deallocate it mid-test
    /// (see CLAUDE.md note on SwiftData test setup).
    private func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Route.self, configurations: config)
    }

    private func makePoints() -> [RoutePoint] {
        // 3-segment toy profile: flat → climb 20m → descend 9m.
        var pts: [RoutePoint] = []
        let step = 5.0
        for i in 0...200 {  // 1000m / 5m = 200 steps
            let d = Double(i) * step
            let ele: Double
            if d <= 300 { ele = 100 }
            else if d <= 700 { ele = 100 + (d - 300) / 400 * 20 }
            else { ele = 120 - (d - 700) / 300 * 9 }
            pts.append(RoutePoint(
                distanceMeters: d, elevationMeters: ele,
                gradePercent: 0,
                latitude: 0, longitude: 0
            ))
        }
        return pts
    }

    @Test
    func aggregateStatsRecomputeFromPointsOnInit() {
        let route = Route(name: "Test", points: makePoints())
        #expect(route.totalDistanceMeters == 1000)
        #expect(abs(route.totalElevationGainMeters - 20) < 0.001)
        #expect(abs(route.totalElevationLossMeters - 9) < 0.001)
        #expect(route.minElevationMeters == 100)
        #expect(abs(route.maxElevationMeters - 120) < 0.001)
    }

    @Test
    func pointsRoundTripThroughBlob() {
        let original = makePoints()
        let route = Route(name: "Test", points: original)
        // pointsData is the encoded form; force a re-decode by clearing the
        // in-memory cache via re-fetch from a fresh model.
        let decoded = (try? JSONDecoder().decode([RoutePoint].self, from: route.pointsData)) ?? []
        #expect(decoded.count == original.count)
        #expect(decoded.first == original.first)
        #expect(decoded.last == original.last)
    }

    @Test
    func emptyPointsArrayResetsStats() {
        let route = Route(name: "Test", points: makePoints())
        route.assignPoints([])
        #expect(route.totalDistanceMeters == 0)
        #expect(route.totalElevationGainMeters == 0)
        #expect(route.totalElevationLossMeters == 0)
        #expect(route.points.isEmpty)
    }

    @Test
    func persistsToSwiftDataAndFetchesBack() throws {
        let container = makeContainer()
        let ctx = container.mainContext

        let route = Route(name: "Persisted", points: makePoints())
        ctx.insert(route)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Route>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Persisted")
        #expect(fetched.first?.points.count == 201)
    }
}
