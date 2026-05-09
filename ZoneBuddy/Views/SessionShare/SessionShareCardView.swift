import SwiftUI
import SwiftData
import UIKit

// MARK: - Component model

/// Reorderable, toggleable metric components on the share card.
/// First 3 enabled (in order) render as large T1 cards; the rest render as compact T2 cards.
enum ShareCardComponent: String, CaseIterable, Identifiable, Codable {
    case avgHR
    case maxHR
    case calories
    case distance
    case avgPower
    case totalOutput
    case zoneAdherence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avgHR:         return "Avg Heart Rate"
        case .maxHR:         return "Max Heart Rate"
        case .calories:      return "Calories"
        case .distance:      return "Distance"
        case .avgPower:      return "Avg Power"
        case .totalOutput:   return "Total Output"
        case .zoneAdherence: return "Zone Adherence"
        }
    }

    var shortLabel: String {
        switch self {
        case .avgHR:         return "AVG HR"
        case .maxHR:         return "MAX HR"
        case .calories:      return "CALORIES"
        case .distance:      return "DISTANCE"
        case .avgPower:      return "AVG POWER"
        case .totalOutput:   return "TOTAL OUTPUT"
        case .zoneAdherence: return "ON TARGET"
        }
    }
}

enum ShareCardColorScheme: String, CaseIterable, Identifiable, Codable {
    case light
    case dark

    var id: String { rawValue }

    var swiftUI: ColorScheme {
        switch self {
        case .light: return .light
        case .dark:  return .dark
        }
    }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }
}

// MARK: - Configuration

/// Display configuration for `SessionShareCardView`. Persisted to UserDefaults so preferences
/// survive across share sessions.
struct SessionShareCardConfiguration: Equatable {
    /// Ordered list of every component with its enabled state.
    /// Index in this array drives tier: first 3 *enabled* items render as T1 large cards,
    /// remaining enabled items render as T2 compact cards.
    var componentSettings: [ComponentSetting]
    var colorScheme: ShareCardColorScheme
    var showZoneBar: Bool
    var showBranding: Bool

    struct ComponentSetting: Codable, Equatable, Identifiable {
        var component: ShareCardComponent
        var isEnabled: Bool
        var id: String { component.id }
    }

    static let `default` = SessionShareCardConfiguration(
        componentSettings: ShareCardComponent.allCases.map { ComponentSetting(component: $0, isEnabled: true) },
        colorScheme: .light,
        showZoneBar: true,
        showBranding: true
    )

    /// Components that are currently enabled, in display order.
    var enabledComponents: [ShareCardComponent] {
        componentSettings.compactMap { $0.isEnabled ? $0.component : nil }
    }

    /// Heals a decoded value: drops duplicates and appends any newly-introduced
    /// `ShareCardComponent` cases (enabled by default) so schema additions/removals
    /// never lose the user's existing order.
    func canonicalized() -> SessionShareCardConfiguration {
        var seen = Set<ShareCardComponent>()
        var settings: [ComponentSetting] = []
        for setting in componentSettings where !seen.contains(setting.component) {
            settings.append(setting)
            seen.insert(setting.component)
        }
        for component in ShareCardComponent.allCases where !seen.contains(component) {
            settings.append(ComponentSetting(component: component, isEnabled: true))
        }
        var copy = self
        copy.componentSettings = settings
        return copy
    }
}

extension SessionShareCardConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case componentSettings, colorScheme, showZoneBar, showBranding
    }

    /// Wrapper that swallows decode failures so unknown component rawValues
    /// (e.g. removed `.maxPower`) drop out cleanly instead of failing the whole config.
    private struct TolerantDecode<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            self.value = try? T(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wrappers = (try? container.decode([TolerantDecode<ComponentSetting>].self, forKey: .componentSettings)) ?? []
        self.componentSettings = wrappers.compactMap(\.value)
        self.colorScheme = (try? container.decode(ShareCardColorScheme.self, forKey: .colorScheme)) ?? .light
        self.showZoneBar = (try? container.decode(Bool.self, forKey: .showZoneBar)) ?? true
        self.showBranding = (try? container.decode(Bool.self, forKey: .showBranding)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(componentSettings, forKey: .componentSettings)
        try container.encode(colorScheme, forKey: .colorScheme)
        try container.encode(showZoneBar, forKey: .showZoneBar)
        try container.encode(showBranding, forKey: .showBranding)
    }
}

// MARK: - Card view

/// A fixed 1080x1080 card designed for offscreen rendering via `ImageRenderer`.
/// Pure function of (session, configuration) — no state, no side effects.
struct SessionShareCardView: View {
    let session: WorkoutSession
    var configuration: SessionShareCardConfiguration = .default

    private static let canvasSize: CGFloat = 1080

    private static var usesMetric: Bool {
        Locale.current.measurementSystem != .us
    }

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 0) {
                hero
                    .padding(.bottom, 40)

                if !largeItems.isEmpty {
                    largeRow
                        .padding(.bottom, compactItems.isEmpty ? 40 : 20)
                }

                if !compactItems.isEmpty {
                    compactRow
                }

                Spacer(minLength: 0)

                if configuration.showZoneBar, !session.sortedIntervals.isEmpty {
                    zoneBar
                        .padding(.bottom, 24)
                }

                if configuration.showBranding {
                    HStack {
                        Spacer()
                        BrandingMark()
                    }
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 64)
            .padding(.bottom, 48)
        }
        .frame(width: Self.canvasSize, height: Self.canvasSize)
        .background(Color(uiColor: .systemBackground))
        .environment(\.colorScheme, configuration.colorScheme.swiftUI)
    }

    // MARK: Background

    private var background: some View {
        let zoneColor = dominantZoneColor
        return LinearGradient(
            colors: [zoneColor.opacity(0.18), zoneColor.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.name.isEmpty {
                Text(session.name)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Text(formattedDate)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
            Text(session.totalDuration.formattedDuration)
                .font(.system(size: 150, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(dominantZoneColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formattedDate: String {
        session.completedAt.formatted(date: .long, time: .omitted)
    }

    // MARK: Component split (order → tier)

    /// Components that are enabled AND have data on the session.
    private var renderableItems: [MetricItem] {
        configuration.enabledComponents.compactMap { metricItem(for: $0) }
    }

    private var largeItems: [MetricItem] {
        Array(renderableItems.prefix(3))
    }

    private var compactItems: [MetricItem] {
        Array(renderableItems.dropFirst(3).prefix(6))
    }

    private var largeRow: some View {
        HStack(spacing: 16) {
            ForEach(largeItems) { item in
                MetricCardLarge(item: item)
            }
        }
    }

    @ViewBuilder
    private var compactRow: some View {
        switch compactItems.count {
        case 0:
            EmptyView()
        case 1...3:
            HStack(spacing: 16) {
                ForEach(compactItems) { item in
                    MetricCardCompact(item: item)
                }
            }
        case 4:
            // 2x2 grid keeps cards roomy when there are exactly four
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(compactItems) { item in
                    MetricCardCompact(item: item)
                }
            }
        default:
            // 5–6: 3-column grid
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(compactItems) { item in
                    MetricCardCompact(item: item)
                }
            }
        }
    }

    private func metricItem(for component: ShareCardComponent) -> MetricItem? {
        switch component {
        case .avgHR:
            guard let v = session.avgHeartRate else { return nil }
            return MetricItem(component: component, label: component.shortLabel, value: "\(v)", unit: "BPM", icon: "heart.fill", accent: .red)
        case .maxHR:
            guard let v = session.maxHeartRate else { return nil }
            return MetricItem(component: component, label: component.shortLabel, value: "\(v)", unit: "BPM", icon: "heart.fill", accent: .red)
        case .calories:
            guard let v = session.totalCalories, v > 0 else { return nil }
            return MetricItem(component: component, label: component.shortLabel, value: "\(v)", unit: "kcal", icon: "flame.fill", accent: .orange)
        case .distance:
            guard let meters = session.totalDistance, meters > 0 else { return nil }
            let value = Self.usesMetric
                ? String(format: "%.1f", meters / 1000.0)
                : String(format: "%.1f", meters / 1609.344)
            let unit = Self.usesMetric ? "km" : "mi"
            return MetricItem(component: component, label: component.shortLabel, value: value, unit: unit, icon: nil, accent: nil)
        case .avgPower:
            guard let v = session.avgPower else { return nil }
            return MetricItem(component: component, label: component.shortLabel, value: "\(v)", unit: "W", icon: nil, accent: nil)
        case .totalOutput:
            guard let kj = session.totalOutputKJ, kj > 0 else { return nil }
            return MetricItem(component: component, label: component.shortLabel, value: String(format: "%.0f", kj), unit: "kJ", icon: nil, accent: nil)
        case .zoneAdherence:
            let scheduled = session.scheduledSecondsByZone.values.reduce(0, +)
            let onTarget = session.onTargetSecondsByZone.values.reduce(0, +)
            guard scheduled > 0 else { return nil }
            let percent = Int((Double(onTarget) / Double(scheduled) * 100).rounded())
            return MetricItem(component: component, label: component.shortLabel, value: "\(percent)", unit: "%", icon: "target", accent: .green)
        }
    }

    // MARK: Zone bar

    private var zoneBar: some View {
        let intervals = session.sortedIntervals
        let total = intervals.reduce(0) { $0 + $1.duration }
        return GeometryReader { geo in
            HStack(spacing: 0) {
                if total > 0 {
                    ForEach(intervals) { interval in
                        Rectangle()
                            .fill(interval.zone?.color ?? Color.gray.opacity(0.4))
                            .frame(width: geo.size.width * CGFloat(interval.duration) / CGFloat(total))
                    }
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }

    // MARK: Dominant zone color

    private var dominantZoneColor: Color {
        if let onTarget = session.onTargetSecondsByZone.max(by: { $0.value < $1.value }),
           onTarget.value > 0 {
            return onTarget.key.color
        }
        if let scheduled = session.scheduledSecondsByZone.max(by: { $0.value < $1.value }),
           scheduled.value > 0 {
            return scheduled.key.color
        }
        return .accentColor
    }
}

// MARK: - Metric Item

private struct MetricItem: Identifiable {
    let component: ShareCardComponent
    let label: String
    let value: String
    let unit: String
    let icon: String?
    let accent: Color?

    var id: String { component.id }
}

// MARK: - Cards

private struct MetricCardLarge: View {
    let item: MetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(item.accent ?? .secondary)
                }
                Text(item.label)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(item.value)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(item.unit)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct MetricCardCompact: View {
    let item: MetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(item.value)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(item.unit)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - Branding mark with iOS-style squircle mask

private struct BrandingMark: View {
    var size: CGFloat = 72

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(AppIconSquircle())
            .opacity(0.9)
    }
}

/// Approximates the iOS app icon mask using a superellipse (n = 5). Closer to Apple's
/// official squircle than `RoundedRectangle(.continuous)`, and tight enough at the corner
/// apex to hide bleed from the source asset.
struct AppIconSquircle: Shape {
    var n: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        let segments = 256
        var path = Path()
        for i in 0...segments {
            let theta = CGFloat(i) / CGFloat(segments) * 2 * .pi
            let cosT = cos(theta)
            let sinT = sin(theta)
            let x = cx + rx * pow(abs(cosT), 2 / n) * (cosT < 0 ? -1 : 1)
            let y = cy + ry * pow(abs(sinT), 2 / n) * (sinT < 0 ? -1 : 1)
            let pt = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
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
            onTargetZoneSeconds: [.zone1: 280, .zone2: 1_080, .zone3: 720, .zone4: 60],
            scheduledZoneSeconds: [.zone1: 300, .zone2: 1_200, .zone3: 900, .zone4: 100],
            hrZoneSeconds: [.zone1: 220, .zone2: 1_100, .zone3: 950, .zone4: 200, .zone5: 30],
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
            avgHeartRate: 148,
            maxHeartRate: 175,
            scheduledZoneSeconds: [.zone1: 300, .zone2: 600, .zone3: 1_200, .zone4: 1_500],
            hrZoneSeconds: [.zone2: 600, .zone3: 1_500, .zone4: 1_200, .zone5: 300],
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

#Preview("Share Card — Light") {
    let (container, session) = makePreviewSession(richBikeData: true)
    return SessionShareCardView(session: session)
        .scaleEffect(0.35)
        .frame(width: 1080 * 0.35, height: 1080 * 0.35)
        .modelContainer(container)
}

#Preview("Share Card — Dark") {
    let (container, session) = makePreviewSession(richBikeData: true)
    var config = SessionShareCardConfiguration.default
    config.colorScheme = .dark
    return SessionShareCardView(session: session, configuration: config)
        .scaleEffect(0.35)
        .frame(width: 1080 * 0.35, height: 1080 * 0.35)
        .modelContainer(container)
}

#Preview("Share Card — HR only") {
    let (container, session) = makePreviewSession(richBikeData: false)
    return SessionShareCardView(session: session)
        .scaleEffect(0.35)
        .frame(width: 1080 * 0.35, height: 1080 * 0.35)
        .modelContainer(container)
}
