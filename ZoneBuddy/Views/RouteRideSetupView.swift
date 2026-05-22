import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RouteRideSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.sortOrder) private var routes: [Route]

    /// Stored as `any BikeConnecting` (Observable) so SwiftUI re-renders when
    /// the trainer connects/disconnects or its caps arrive. Matches the
    /// dependency-injection pattern used by `SettingsView`, `BikePromptSheet`.
    private var bikeManager: any BikeConnecting = BikeManagerProvider.current

    @State private var showImporter = false
    @State private var selectedRoute: Route?
    @State private var importError: String?
    @State private var showingBikePrompt = false
    @State private var routeAwaitingStart: Route?
    @State private var showingTrainerRequiredAlert = false

    /// `.gpx` UTType. The OS doesn't ship a built-in GPX type, so we
    /// derive one from the file extension and conform it to `.xml`.
    private static let gpxType = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml

    var body: some View {
        List {
            if !isTrainerReady {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart Trainer Required")
                                .font(.subheadline.weight(.semibold))
                            Text(trainerRequirementMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if routes.isEmpty {
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Export a route as GPX from Ride With GPS (or any GPX-aware app) and import it here.")
                }
            } else {
                Section {
                    ForEach(routes) { route in
                        Button {
                            startRoute(route)
                        } label: {
                            RouteRow(route: route)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .disabled(!isTrainerReady)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Route Ride")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !routes.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [Self.gpxType, .xml],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Smart Trainer Required", isPresented: $showingTrainerRequiredAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(trainerRequirementMessage)
        }
        .navigationDestination(item: $selectedRoute) { route in
            WorkoutPlayerView(
                intervals: [],
                workoutName: route.name,
                mode: .routeRide(routeID: route.id)
            )
        }
        .sheet(isPresented: $showingBikePrompt) {
            BikePromptSheet(onStart: {
                showingBikePrompt = false
                if let pending = routeAwaitingStart {
                    selectedRoute = pending
                    routeAwaitingStart = nil
                }
            })
        }
    }

    /// True when a trainer that can apply grade resistance is currently
    /// connected. Route Ride is impossible without one, so both the row tap
    /// and the row's enabled state hang off this.
    private var isTrainerReady: Bool {
        guard bikeManager.isConnected else { return false }
        return bikeManager.trainerController?.capabilities?.simulationParamsSupported == true
    }

    private var trainerRequirementMessage: String {
        if !bikeManager.isConnected {
            return "Route Ride applies grade resistance through a smart trainer. Connect your trainer in Settings to start a route."
        }
        return "The connected trainer doesn't support grade simulation. Connect a smart trainer that supports FTMS Indoor Bike Simulation to ride routes."
    }

    private func startRoute(_ route: Route) {
        guard isTrainerReady else {
            showingTrainerRequiredAlert = true
            return
        }
        let promptEnabled = SettingsManager.shared.promptForBikeBeforeWorkout
        let bikeReady = bikeManager.isConnected && bikeManager.hasReceivedNonZeroMetric
        if promptEnabled && !bikeReady {
            routeAwaitingStart = route
            showingBikePrompt = true
        } else {
            selectedRoute = route
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let name = url.deletingPathExtension().lastPathComponent
                let route = try GPXParser.makeRoute(name: name, from: data)
                // Pin new routes to the top.
                for existing in routes { existing.sortOrder += 1 }
                route.sortOrder = 0
                modelContext.insert(route)
                try modelContext.save()
            } catch let err as GPXParseError {
                importError = friendlyMessage(for: err)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let err):
            importError = err.localizedDescription
        }
    }

    private func friendlyMessage(for err: GPXParseError) -> String {
        switch err {
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

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(routes[index])
        }
        // Re-index so the next import lands at sortOrder = 0 without
        // colliding with a stale value.
        for (index, route) in routes.enumerated() {
            route.sortOrder = index
        }
        try? modelContext.save()
    }
}

private struct RouteRow: View {
    let route: Route

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mountain.2.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.headline)
                HStack(spacing: 12) {
                    Label(UnitFormatting.distance(meters: route.totalDistanceMeters),
                          systemImage: "ruler")
                        .labelStyle(.titleAndIcon)
                    Label(elevationGainLabel,
                          systemImage: "arrow.up.right")
                        .labelStyle(.titleAndIcon)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var elevationGainLabel: String {
        if UnitFormatting.usesMetric {
            return "\(Int(route.totalElevationGainMeters)) m"
        } else {
            return "\(Int(route.totalElevationGainMeters * 3.28084)) ft"
        }
    }
}

#Preview {
    NavigationStack {
        RouteRideSetupView()
            .modelContainer(for: Route.self, inMemory: true)
    }
}
