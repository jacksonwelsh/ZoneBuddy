import SwiftUI
import SwiftData

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.completedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            List {
                if DataStore.shared.isCloudKitDisabled {
                    Section {
                        iCloudDisabledBanner
                            .listRowBackground(Color.orange.opacity(0.12))
                    }
                }
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        WorkoutHistoryRow(session: session)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(sessions[index])
                    }
                    try? modelContext.save()
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Completed workouts will appear here.")
                    )
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: WorkoutSession.self) { session in
                WorkoutSessionDetailView(session: session)
            }
        }
    }

    private var iCloudDisabledBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("iCloud Sync Off")
                    .font(.headline)
                Text("This device couldn't connect to iCloud, so new sessions won't sync to your other devices. Try restarting the app, or check that you're signed into iCloud with ZoneBuddy enabled in Settings › Apple Account › iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WorkoutHistoryRow: View {
    let session: WorkoutSession

    private var subtitle: String {
        let date = session.completedAt.formatted(.relative(presentation: .named))
        return "\(date) \u{2022} \(session.totalDuration.formattedDuration)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.name.isEmpty ? "Workout" : session.name)
                            .font(.headline)
                        if case .ftpTest(let kind, _) = session.modality {
                            FTPProtocolChip(kind: kind)
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trailingMetrics
            }

            switch session.modality {
            case .structured:
                // Structured workouts: show on-target adherence — how well the
                // rider held the prescribed zone, not just where they were.
                ZoneBreakdownBar(secondsByZone: session.onTargetSecondsByZone)
            case .freeRide, .routeRide:
                // Unstructured rides have no prescribed zone, so "on-target"
                // is always empty. Show actual time spent in each zone
                // (sourced from `zoneTimeAccumulator` at persist time).
                ZoneBreakdownBar(secondsByZone: session.scheduledSecondsByZone)
            case .ftpTest:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var trailingMetrics: some View {
        switch session.modality {
        case .ftpTest(_, let result):
            ftpTrailingMetric(result: result)
        case .structured, .freeRide, .routeRide:
            workoutTrailingMetrics
        }
    }

    @ViewBuilder
    private func ftpTrailingMetric(result: FTPTestResult?) -> some View {
        if let result {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(result.measuredFTP)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("W FTP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\u{2014}")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("No result")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var workoutTrailingMetrics: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let avg = session.avgPower {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(avg)")
                        .font(.headline)
                        .monospacedDigit()
                    Text("W avg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let kj = session.totalOutputKJ, kj > 0 {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", kj))
                        .font(.subheadline)
                        .monospacedDigit()
                    Text("kJ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct FTPProtocolChip: View {
    let kind: FTPTestKind

    private var label: String {
        switch kind {
        case .twentyMinute: return "20-min"
        case .ramp: return "Ramp"
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

/// Compact horizontal stacked bar showing on-target seconds per power zone.
struct ZoneBreakdownBar: View {
    let secondsByZone: [PowerZone: Int]

    private var totalSeconds: Int {
        secondsByZone.values.reduce(0, +)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                if totalSeconds > 0 {
                    ForEach(PowerZone.allCases) { zone in
                        let seconds = secondsByZone[zone] ?? 0
                        if seconds > 0 {
                            Rectangle()
                                .fill(zone.color)
                                .frame(width: geo.size.width * CGFloat(seconds) / CGFloat(totalSeconds))
                        }
                    }
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.2))
                }
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
    }
}

// MARK: - Previews

private func makePreviewContainer(populated: Bool) -> ModelContainer {
    let container = try! ModelContainer(
        for: WorkoutSession.self, SessionInterval.self, Workout.self, Interval.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    guard populated else { return container }

    let context = container.mainContext
    let now = Date()
    let day: TimeInterval = 86_400

    let endurance = WorkoutSession(
        name: "Power Zone Endurance",
        transitionWarningDuration: 10,
        completedAt: now.addingTimeInterval(-day * 0.2),
        totalDuration: 45 * 60,
        avgPower: 178,
        maxPower: 312,
        totalOutputKJ: 480,
        totalDistance: 18_500,
        totalCalories: 520,
        avgHeartRate: 142,
        maxHeartRate: 168,
        onTargetZoneSeconds: [
            .zone1: 280,
            .zone2: 1_180,
            .zone3: 720,
            .zone4: 60,
        ],
        scheduledZoneSeconds: [
            .zone1: 300,
            .zone2: 1_200,
            .zone3: 900,
            .zone4: 100,
        ],
        hrZoneSeconds: [
            .zone1: 220,
            .zone2: 1_100,
            .zone3: 950,
            .zone4: 200,
            .zone5: 30,
        ],
        ftpAtTime: 220,
        maxHRAtTime: 188,
        bikeWasConnected: true
    )
    endurance.intervals = [
        SessionInterval(zone: nil, duration: 300, sortOrder: 0),
        SessionInterval(zone: .zone2, duration: 1_200, sortOrder: 1),
        SessionInterval(zone: .zone3, duration: 900, sortOrder: 2),
        SessionInterval(zone: .zone1, duration: 300, sortOrder: 3),
    ]

    let max = WorkoutSession(
        name: "PZ Max Intervals",
        transitionWarningDuration: 10,
        completedAt: now.addingTimeInterval(-day * 3),
        totalDuration: 30 * 60,
        avgPower: 215,
        maxPower: 480,
        totalOutputKJ: 388,
        totalDistance: 12_900,
        totalCalories: 410,
        avgHeartRate: 156,
        maxHeartRate: 184,
        onTargetZoneSeconds: [
            .zone2: 240,
            .zone3: 360,
            .zone4: 380,
            .zone5: 240,
            .zone6: 110,
        ],
        scheduledZoneSeconds: [
            .zone2: 300,
            .zone3: 360,
            .zone4: 480,
            .zone5: 300,
            .zone6: 180,
        ],
        hrZoneSeconds: [
            .zone2: 180,
            .zone3: 540,
            .zone4: 720,
            .zone5: 360,
        ],
        ftpAtTime: 220,
        maxHRAtTime: 188,
        bikeWasConnected: true
    )

    let recovery = WorkoutSession(
        name: "Recovery Spin",
        transitionWarningDuration: 5,
        completedAt: now.addingTimeInterval(-day * 7),
        totalDuration: 20 * 60,
        avgPower: 95,
        maxPower: 160,
        totalOutputKJ: 114,
        totalDistance: 7_300,
        totalCalories: 145,
        avgHeartRate: 118,
        maxHeartRate: 138,
        onTargetZoneSeconds: [.zone1: 1_080],
        scheduledZoneSeconds: [.zone1: 1_200],
        hrZoneSeconds: [.zone1: 720, .zone2: 480],
        ftpAtTime: 220,
        maxHRAtTime: 188,
        bikeWasConnected: true
    )

    let bikeFree = WorkoutSession(
        name: "Threshold Builder",
        transitionWarningDuration: 10,
        completedAt: now.addingTimeInterval(-day * 14),
        totalDuration: 60 * 60,
        avgPower: nil,
        maxPower: nil,
        totalOutputKJ: nil,
        totalDistance: nil,
        totalCalories: nil,
        avgHeartRate: 148,
        maxHeartRate: 175,
        onTargetZoneSeconds: [:],
        scheduledZoneSeconds: [
            .zone2: 600,
            .zone3: 1_200,
            .zone4: 1_500,
            .zone1: 300,
        ],
        hrZoneSeconds: [
            .zone2: 600,
            .zone3: 1_500,
            .zone4: 1_200,
            .zone5: 300,
        ],
        ftpAtTime: 220,
        maxHRAtTime: 188,
        bikeWasConnected: false
    )

    let rampTest = WorkoutSession(
        name: "FTP Ramp Test",
        transitionWarningDuration: 10,
        completedAt: now.addingTimeInterval(-day * 1),
        totalDuration: 18 * 60,
        avgPower: 240,
        maxPower: 380,
        totalOutputKJ: 260,
        totalDistance: 7_200,
        totalCalories: 290,
        avgHeartRate: 158,
        maxHeartRate: 184,
        ftpAtTime: 220,
        maxHRAtTime: 188,
        bikeWasConnected: true,
        modality: .ftpTest(
            protocol: .ramp,
            result: FTPTestResult(measuredFTP: 255, sourcePower: 340)
        )
    )

    let twentyMinTest = WorkoutSession(
        name: "FTP Test",
        transitionWarningDuration: 10,
        completedAt: now.addingTimeInterval(-day * 30),
        totalDuration: 45 * 60,
        avgPower: 230,
        maxPower: 320,
        totalOutputKJ: 620,
        totalDistance: 18_000,
        totalCalories: 540,
        avgHeartRate: 162,
        maxHeartRate: 178,
        ftpAtTime: 220,
        maxHRAtTime: 188,
        bikeWasConnected: true,
        modality: .ftpTest(
            protocol: .twentyMinute,
            result: FTPTestResult(measuredFTP: 245, sourcePower: 258)
        )
    )

    let abortedTest = WorkoutSession(
        name: "FTP Ramp Test",
        transitionWarningDuration: 10,
        completedAt: now.addingTimeInterval(-day * 45),
        totalDuration: 6 * 60,
        avgPower: 140,
        maxPower: 190,
        avgHeartRate: 124,
        maxHeartRate: 142,
        ftpAtTime: 220,
        maxHRAtTime: 188,
        bikeWasConnected: true,
        modality: .ftpTest(protocol: .ramp, result: nil)
    )

    [endurance, max, recovery, bikeFree, rampTest, twentyMinTest, abortedTest].forEach { context.insert($0) }
    endurance.intervals?.forEach { context.insert($0) }
    try? context.save()
    return container
}

#Preview("Empty") {
    WorkoutHistoryView()
        .modelContainer(makePreviewContainer(populated: false))
}

#Preview("With Sessions") {
    WorkoutHistoryView()
        .modelContainer(makePreviewContainer(populated: true))
}

#Preview("Row — Bike + HR") {
    let container = makePreviewContainer(populated: true)
    let session = (try? container.mainContext.fetch(
        FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
    ))?.first
    return List {
        if let session {
            WorkoutHistoryRow(session: session)
        }
    }
    .modelContainer(container)
}
