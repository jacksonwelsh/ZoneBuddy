import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RouteRideSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.sortOrder) private var routes: [Route]

    @State private var showImporter = false
    @State private var selectedRoute: Route?
    @State private var importError: String?

    /// `.gpx` UTType. The OS doesn't ship a built-in GPX type, so we
    /// derive one from the file extension and conform it to `.xml`.
    private static let gpxType = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml

    var body: some View {
        List {
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
                            selectedRoute = route
                        } label: {
                            RouteRow(route: route)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
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
        .navigationDestination(item: $selectedRoute) { route in
            RouteRidePreviewView(route: route)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try RouteImporter.importRoute(from: url, into: modelContext)
            } catch let err as GPXParseError {
                importError = err.userFacingMessage
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let err):
            importError = err.localizedDescription
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
                    metric(UnitFormatting.distance(meters: route.totalDistanceMeters),
                           systemImage: "ruler")
                    metric(elevationGainLabel, systemImage: "arrow.up.right")
                    metric(estimateLabel, systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Icon + value with tight spacing. `Label`'s default icon-title gap reads
    /// as a stray space in these compact metric rows, so we lay it out by hand.
    private func metric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(value)
        }
    }

    private var elevationGainLabel: String {
        if UnitFormatting.usesMetric {
            return "\(Int(route.totalElevationGainMeters)) m"
        } else {
            return "\(Int(route.totalElevationGainMeters * 3.28084)) ft"
        }
    }

    private var estimateLabel: String {
        let seconds = RouteRideEstimator.estimatedSeconds(
            points: route.points,
            ftp: SettingsManager.shared.functionalThresholdPower,
            riderWeightKg: SettingsManager.shared.riderWeightKg
        )
        return RouteRideEstimator.formattedEstimate(seconds: seconds)
    }
}

#Preview {
    NavigationStack {
        RouteRideSetupView()
            .modelContainer(for: Route.self, inMemory: true)
    }
}
