import Foundation
import SwiftData

/// Turns a GPX file on disk into a persisted `Route`. Shared by the in-app
/// file importer (`RouteRideSetupView`) and the system "Open with ZoneBuddy"
/// handler (`onOpenURL` in `ZoneBuddyApp`) so both paths apply identical
/// security-scope handling, naming, and top-of-list ordering.
enum RouteImporter {
    /// Read the GPX at `url`, parse it, insert the resulting `Route` at the top
    /// of the route list, and persist. Returns the inserted route.
    ///
    /// Throws `GPXParseError` for bad/empty/oversized GPX, or the underlying
    /// `Data(contentsOf:)` error if the file can't be read.
    @MainActor
    @discardableResult
    static func importRoute(from url: URL, into context: ModelContext) throws -> Route {
        // Files handed to us by the Files app / share sheet are security-scoped;
        // we must bracket the read in start/stop calls or `Data(contentsOf:)`
        // fails with a permission error.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        let route = try GPXParser.makeRoute(name: name, from: data)

        // Pin the new route to the top, bumping everything else down one slot.
        let existing = (try? context.fetch(FetchDescriptor<Route>())) ?? []
        for r in existing { r.sortOrder += 1 }
        route.sortOrder = 0

        context.insert(route)
        try context.save()
        return route
    }
}

extension GPXParseError {
    /// User-presentable explanation, used by every GPX import entry point.
    var userFacingMessage: String {
        switch self {
        case .unreadable:
            return "The file was empty or couldn't be read."
        case .noTrackPoints:
            return "This file has no track points to ride. Make sure you exported a route or a recorded activity (not just a list of waypoints)."
        case .malformedXML(let detail):
            return "The file isn't valid GPX (\(detail))."
        case .tooLarge(let bytes):
            let mb = Double(bytes) / 1_048_576
            return String(format: "This file is too large to import (%.1f MB).", mb)
        }
    }
}
