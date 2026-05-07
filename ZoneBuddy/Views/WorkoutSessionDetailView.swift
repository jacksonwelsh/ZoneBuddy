import SwiftUI
import SwiftData

struct WorkoutSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession

    @State private var showDeleteConfirm = false

    private static var usesMetric: Bool {
        Locale.current.measurementSystem != .us
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                structureSection
                metricsGrid
                powerZoneSection
                hrZoneSection
            }
            .padding()
        }
        .navigationTitle(session.name.isEmpty ? "Workout" : session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(session)
                try? modelContext.save()
                dismiss()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.completedAt.formatted(date: .complete, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(session.totalDuration.formattedDuration)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var structureSection: some View {
        let snapshot = session.sortedIntervals
        if !snapshot.isEmpty {
            let totalSnapshotDuration = snapshot.reduce(0) { $0 + $1.duration }
            VStack(alignment: .leading, spacing: 8) {
                Text("Workout Structure")
                    .font(.headline)
                SessionIntervalProgressionBar(
                    intervals: snapshot,
                    totalDuration: totalSnapshotDuration
                )
            }
        }
    }

    @ViewBuilder
    private var metricsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            if let avg = session.avgPower {
                MetricCell(label: "AVG POWER", value: "\(avg)", unit: "W")
            }
            if let max = session.maxPower {
                MetricCell(label: "MAX POWER", value: "\(max)", unit: "W")
            }
            if let kj = session.totalOutputKJ, kj > 0 {
                MetricCell(label: "TOTAL OUTPUT", value: String(format: "%.0f", kj), unit: "kJ")
            }
            if let distance = session.totalDistance, distance > 0 {
                MetricCell(
                    label: "DISTANCE",
                    value: formattedDistance(distance),
                    unit: Self.usesMetric ? "km" : "mi"
                )
            }
            if let calories = session.totalCalories, calories > 0 {
                MetricCell(label: "CALORIES", value: "\(calories)", unit: "kcal")
            }
            if let avgHR = session.avgHeartRate {
                MetricCell(label: "AVG HR", value: "\(avgHR)", unit: "BPM")
            }
            if let maxHR = session.maxHeartRate {
                MetricCell(label: "MAX HR", value: "\(maxHR)", unit: "BPM")
            }
        }
    }

    private var powerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Power Zones — On-Target")
                .font(.headline)
            Text("Time you held the prescribed zone during each target interval.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(PowerZone.allCases) { zone in
                    let scheduled = session.scheduledSecondsByZone[zone] ?? 0
                    if scheduled > 0 {
                        let onTarget = session.onTargetSecondsByZone[zone] ?? 0
                        PowerZoneAdherenceRow(
                            zone: zone,
                            onTargetSeconds: onTarget,
                            scheduledSeconds: scheduled
                        )
                    }
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            }
        }
    }

    private var hrZoneSection: some View {
        let total = session.hrSecondsByZone.values.reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate Zones")
                .font(.headline)
            Text("Total time spent in each HR zone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if total == 0 {
                Text("No heart rate data was recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(HeartRateZone.allCases) { zone in
                        let seconds = session.hrSecondsByZone[zone] ?? 0
                        HeartRateZoneRow(zone: zone, seconds: seconds, totalSeconds: total)
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }
            }
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        if Self.usesMetric {
            return String(format: "%.1f", meters / 1000.0)
        }
        return String(format: "%.1f", meters / 1609.344)
    }
}

// MARK: - Row Components

private struct MetricCell: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
    }
}

private struct PowerZoneAdherenceRow: View {
    let zone: PowerZone
    let onTargetSeconds: Int
    let scheduledSeconds: Int

    private var fraction: Double {
        guard scheduledSeconds > 0 else { return 0 }
        return min(Double(onTargetSeconds) / Double(scheduledSeconds), 1.0)
    }

    private var percent: Int {
        Int((fraction * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Z\(zone.rawValue) \u{2022} \(zone.zoneName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(zone.labelColor)
                Spacer()
                Text("\(onTargetSeconds.formattedDuration) / \(scheduledSeconds.formattedDuration)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("\(percent)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(zone.labelColor)
                    .frame(width: 40, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(zone.color.opacity(0.15))
                    Capsule()
                        .fill(zone.color)
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 8)
        }
    }
}

struct SessionIntervalProgressionBar: View {
    let intervals: [SessionInterval]
    let totalDuration: Int

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if totalDuration > 0 {
                    ForEach(intervals) { interval in
                        Rectangle()
                            .fill(interval.zone?.color ?? Color.gray)
                            .frame(width: geometry.size.width * CGFloat(interval.duration) / CGFloat(totalDuration))
                    }
                } else {
                    Color.clear
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

private struct HeartRateZoneRow: View {
    let zone: HeartRateZone
    let seconds: Int
    let totalSeconds: Int

    private var fraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(seconds) / Double(totalSeconds)
    }

    private var percent: Int {
        Int((fraction * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Z\(zone.rawValue) \u{2022} \(zone.zoneName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(zone.color)
                Spacer()
                Text(seconds.formattedDuration)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("\(percent)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(zone.color)
                    .frame(width: 40, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(zone.color.opacity(0.15))
                    Capsule()
                        .fill(zone.color)
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Previews

@MainActor
private func makePreviewSession(richBikeData: Bool) -> (ModelContainer, WorkoutSession) {
    let container = try! ModelContainer(
        for: WorkoutSession.self, SessionInterval.self, Workout.self, Interval.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let session: WorkoutSession
    if richBikeData {
        session = WorkoutSession(
            name: "Power Zone Endurance",
            transitionWarningDuration: 10,
            completedAt: Date().addingTimeInterval(-3_600 * 5),
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
                .zone2: 1_080,
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
        session.intervals = [
            SessionInterval(zone: nil, duration: 300, sortOrder: 0),
            SessionInterval(zone: .zone2, duration: 1_200, sortOrder: 1),
            SessionInterval(zone: .zone3, duration: 900, sortOrder: 2),
            SessionInterval(zone: .zone4, duration: 100, sortOrder: 3),
            SessionInterval(zone: .zone1, duration: 300, sortOrder: 4),
        ]
    } else {
        session = WorkoutSession(
            name: "Threshold Builder",
            transitionWarningDuration: 10,
            completedAt: Date().addingTimeInterval(-3_600 * 26),
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
        session.intervals = [
            SessionInterval(zone: nil, duration: 300, sortOrder: 0),
            SessionInterval(zone: .zone2, duration: 600, sortOrder: 1),
            SessionInterval(zone: .zone3, duration: 1_200, sortOrder: 2),
            SessionInterval(zone: .zone4, duration: 1_500, sortOrder: 3),
            SessionInterval(zone: .zone1, duration: 300, sortOrder: 4),
        ]
    }

    context.insert(session)
    session.intervals?.forEach { context.insert($0) }
    try? context.save()
    return (container, session)
}

#Preview("iPhone \u{2014} Bike + HR") {
    let (container, session) = makePreviewSession(richBikeData: true)
    return NavigationStack {
        WorkoutSessionDetailView(session: session)
    }
    .modelContainer(container)
    .previewDevice(PreviewDevice(rawValue: "iPhone 17 Pro"))
}

#Preview("iPhone \u{2014} HR only") {
    let (container, session) = makePreviewSession(richBikeData: false)
    return NavigationStack {
        WorkoutSessionDetailView(session: session)
    }
    .modelContainer(container)
    .previewDevice(PreviewDevice(rawValue: "iPhone 17 Pro"))
}

#Preview("iPad \u{2014} Bike + HR") {
    let (container, session) = makePreviewSession(richBikeData: true)
    return NavigationStack {
        WorkoutSessionDetailView(session: session)
    }
    .modelContainer(container)
    .previewDevice(PreviewDevice(rawValue: "iPad Pro 13-inch (M5)"))
}

#Preview("iPad \u{2014} HR only") {
    let (container, session) = makePreviewSession(richBikeData: false)
    return NavigationStack {
        WorkoutSessionDetailView(session: session)
    }
    .modelContainer(container)
    .previewDevice(PreviewDevice(rawValue: "iPad Pro 13-inch (M5)"))
}
