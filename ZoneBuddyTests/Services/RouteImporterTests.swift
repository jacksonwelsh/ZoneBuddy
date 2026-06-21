import Testing
import Foundation
import SwiftData
@testable import ZoneBuddy

@MainActor
struct RouteImporterTests {

    /// Retain the container so SwiftData doesn't deallocate it mid-test
    /// (see CLAUDE.md note on SwiftData test setup).
    private func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Route.self, configurations: config)
    }

    private static let sampleGPX = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="test">
      <trk>
        <trkseg>
          <trkpt lat="40.0000" lon="-105.0000"><ele>1600.0</ele></trkpt>
          <trkpt lat="40.0010" lon="-105.0000"><ele>1602.0</ele></trkpt>
          <trkpt lat="40.0020" lon="-105.0000"><ele>1610.0</ele></trkpt>
          <trkpt lat="40.0030" lon="-105.0000"><ele>1605.0</ele></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    /// Write `contents` to a uniquely-named temp file with `ext` and return it.
    private func writeTempFile(name: String, ext: String, contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name).appendingPathExtension(ext)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test
    func importsRouteAndNamesItFromFilename() throws {
        let container = makeContainer()
        let context = container.mainContext
        let url = try writeTempFile(name: "Old La Honda", ext: "gpx", contents: Self.sampleGPX)

        let route = try RouteImporter.importRoute(from: url, into: context)

        #expect(route.name == "Old La Honda")
        #expect(!route.points.isEmpty)
        #expect(route.totalDistanceMeters > 0)
        // The route was persisted.
        let stored = try context.fetch(FetchDescriptor<Route>())
        #expect(stored.count == 1)
        #expect(stored.first?.id == route.id)
    }

    @Test
    func pinsNewImportToTopOfList() throws {
        let container = makeContainer()
        let context = container.mainContext

        let first = try RouteImporter.importRoute(
            from: try writeTempFile(name: "First", ext: "gpx", contents: Self.sampleGPX),
            into: context
        )
        let second = try RouteImporter.importRoute(
            from: try writeTempFile(name: "Second", ext: "gpx", contents: Self.sampleGPX),
            into: context
        )

        // Newest import sits at sortOrder 0; the earlier one is bumped down.
        #expect(second.sortOrder == 0)
        #expect(first.sortOrder == 1)
    }

    @Test
    func throwsParseErrorForFileWithNoTrackPoints() throws {
        let container = makeContainer()
        let context = container.mainContext
        let waypointOnly = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><wpt lat="40" lon="-105"><ele>1000</ele></wpt></gpx>
        """
        let url = try writeTempFile(name: "Waypoints", ext: "gpx", contents: waypointOnly)

        #expect(throws: GPXParseError.noTrackPoints) {
            try RouteImporter.importRoute(from: url, into: context)
        }
        // Nothing was persisted on failure.
        #expect((try context.fetch(FetchDescriptor<Route>())).isEmpty)
    }

    @Test
    func userFacingMessagesAreNonEmpty() {
        let cases: [GPXParseError] = [
            .unreadable,
            .noTrackPoints,
            .malformedXML("line 3"),
            .tooLarge(bytes: 6 * 1024 * 1024),
        ]
        for err in cases {
            #expect(!err.userFacingMessage.isEmpty)
        }
        // The malformed detail is surfaced to the user.
        #expect(GPXParseError.malformedXML("line 3").userFacingMessage.contains("line 3"))
    }
}
