import SwiftUI
import SwiftData

/// Shown when the user taps a route in `RouteRideSetupView`. Lets them inspect
/// the route's shape and stats before committing to the ride. Previewing is
/// always allowed; the smart-trainer requirement is enforced only when the
/// rider taps "Start Ride" (FTP-test style — declare intent, then connect).
struct RouteRidePreviewView: View {
    let route: Route

    /// `any BikeConnecting` (Observable) so the trainer notice + Start gating
    /// re-render when a trainer connects/disconnects or its caps arrive.
    var bikeManager: any BikeConnecting = BikeManagerProvider.current

    @Environment(\.modelContext) private var modelContext

    @State private var routeToStart: Route?
    @State private var showingBikePrompt = false
    @State private var showingTrainerRequiredAlert = false
    @State private var showingRename = false
    @State private var draftName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                ElevationProfileView(
                    route: route,
                    currentDistanceMeters: 0,
                    showCursor: false
                )
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                statsGrid
                if !isTrainerReady {
                    trainerNotice
                }
            }
            .padding(20)
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    draftName = route.name
                    showingRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            startButton
        }
        .navigationDestination(item: $routeToStart) { route in
            WorkoutPlayerView(
                intervals: [],
                workoutName: route.name,
                mode: .routeRide(routeID: route.id)
            )
        }
        .sheet(isPresented: $showingBikePrompt) {
            BikePromptSheet(
                bikeManager: bikeManager,
                requireBike: true,
                onStart: {
                    showingBikePrompt = false
                    // BikePromptSheet's required mode only guarantees non-zero
                    // metrics, not grade-sim support — so re-check here.
                    if isTrainerReady {
                        routeToStart = route
                    } else {
                        showingTrainerRequiredAlert = true
                    }
                }
            )
        }
        .alert("Smart Trainer Required", isPresented: $showingTrainerRequiredAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(trainerRequirementMessage)
        }
        .alert("Rename Route", isPresented: $showingRename) {
            TextField("Route name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { applyRename() }
        }
    }

    private func applyRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        route.name = trimmed
        try? modelContext.save()
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            Text("Ride This Route")
                .font(.title2.weight(.bold))
            Text("Your trainer adjusts grade resistance to match the terrain as you ride. Tap the profile to switch between elevation and grade.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                statTile(value: distanceLabel, caption: "DISTANCE")
                statTile(value: estimatedTimeLabel, caption: "EST. TIME")
            }
            HStack(spacing: 12) {
                statTile(value: gainLabel, caption: "ELEV. GAIN")
                statTile(value: lossLabel, caption: "ELEV. LOSS")
                statTile(
                    value: maxGradeLabel,
                    caption: "MAX GRADE",
                    color: ElevationProfileView.gradeColor(maxGrade)
                )
            }
        }
    }

    private func statTile(value: String, caption: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var trainerNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Trainer Required")
                    .font(.subheadline.weight(.semibold))
                Text(trainerRequirementMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var startButton: some View {
        Button {
            if isTrainerReady {
                routeToStart = route
            } else {
                showingBikePrompt = true
            }
        } label: {
            Text("Start Ride")
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Gating

    /// True when a connected trainer can apply grade resistance. Route Ride is
    /// impossible without one. Lifted from `RouteRideSetupView`.
    private var isTrainerReady: Bool {
        guard bikeManager.isConnected else { return false }
        return bikeManager.trainerController?.capabilities?.simulationParamsSupported == true
    }

    private var trainerRequirementMessage: String {
        if !bikeManager.isConnected {
            return "Route Ride applies grade resistance through a smart trainer. Connect your trainer to start a route."
        }
        return "The connected trainer doesn't support grade simulation. Connect a smart trainer that supports FTMS Indoor Bike Simulation to ride routes."
    }

    // MARK: - Stat labels

    private var distanceLabel: String {
        "\(UnitFormatting.distance(meters: route.totalDistanceMeters)) \(UnitFormatting.distanceUnit)"
    }

    private var gainLabel: String { elevationLabel(route.totalElevationGainMeters) }
    private var lossLabel: String { elevationLabel(route.totalElevationLossMeters) }

    private func elevationLabel(_ meters: Double) -> String {
        if UnitFormatting.usesMetric {
            return "\(Int(meters)) m"
        } else {
            return "\(Int(meters * 3.28084)) ft"
        }
    }

    private var maxGrade: Double {
        route.points.map(\.gradePercent).max() ?? 0
    }

    private var maxGradeLabel: String {
        String(format: "%+.1f%%", maxGrade)
    }

    private var estimatedTimeLabel: String {
        let seconds = RouteRideEstimator.estimatedSeconds(
            points: route.points,
            ftp: SettingsManager.shared.functionalThresholdPower,
            riderWeightKg: SettingsManager.shared.riderWeightKg
        )
        return RouteRideEstimator.formattedEstimate(seconds: seconds)
    }
}

#Preview {
    var points: [RoutePoint] = []
    for i in 0...400 {
        let d = Double(i) * 5
        let grade = sin(d / 800) * 7
        let ele = 100 + cos(d / 600) * 40
        points.append(RoutePoint(
            distanceMeters: d, elevationMeters: ele, gradePercent: grade,
            latitude: 37 + d / 100_000, longitude: -122
        ))
    }
    return NavigationStack {
        RouteRidePreviewView(route: Route(name: "Old La Honda", points: points))
    }
}
