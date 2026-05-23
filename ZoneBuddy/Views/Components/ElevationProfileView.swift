import SwiftUI
import Charts

/// Renders a route's elevation profile as a coloured area chart with a
/// vertical cursor at the rider's current distance. Decimates the input
/// points so the chart stays responsive on routes with thousands of samples.
struct ElevationProfileView: View {
    let route: Route
    /// 0...totalDistanceMeters — drives the position cursor.
    let currentDistanceMeters: Double
    /// Hides the cursor (used when previewing a route before starting it).
    var showCursor: Bool = true
    /// If set, only the route up to this distance is rendered in colour;
    /// everything past is drawn in gray. Used by the history detail view
    /// to indicate the user only rode part of the route. Pass `nil` (default)
    /// to colour the whole route.
    var completedDistanceMeters: Double? = nil

    private static let maxRenderedPoints = 500
    /// Width of the sliding window in zoomed mode. One mile — the user said
    /// "one mile" specifically, so we don't locale-switch this to a kilometre.
    private static let zoomWindowMeters: Double = 1609.344

    /// Pre-decimated sample array. Computed lazily and cached on each
    /// `route` change so the chart isn't asked to render 10 k AreaMarks.
    @State private var renderedPoints: [RoutePoint] = []

    /// Same points split into contiguous runs of the same grade bucket.
    /// Each run is rendered as its own Charts series so adjacent colours
    /// don't bleed across the whole x-range — without this, a single
    /// `foregroundStyle(by:)` on AreaMark causes every category to stretch
    /// from x=0 to x=last, painting the chart in overlapping rainbows.
    @State private var segments: [RouteElevationSegment] = []

    /// Tap-to-cycle between the three render modes. Only the cursored modes
    /// are reachable — `showCursor == false` (post-ride summary) leaves the
    /// view stuck in `.elevation`.
    @State private var displayMode: DisplayMode = .elevation

    var body: some View {
        Chart {
            if displayMode == .gradeLine {
                ForEach(renderedPoints, id: \.distanceMeters) { point in
                    LineMark(
                        x: .value("Distance", point.distanceMeters),
                        y: .value("Grade", point.gradePercent)
                    )
                    .foregroundStyle(.white)
                    .interpolationMethod(.monotone)
                }
            } else {
                ForEach(displayedSegments) { segment in
                    ForEach(segment.points, id: \.distanceMeters) { point in
                        AreaMark(
                            x: .value("Distance", point.distanceMeters),
                            yStart: .value("Min", route.minElevationMeters - 5),
                            yEnd: .value("Elevation", point.elevationMeters),
                            series: .value("Segment", segment.id)
                        )
                        .foregroundStyle(segment.color)
                        .interpolationMethod(.monotone)
                    }
                }
            }
            if showCursor {
                RuleMark(x: .value("Position", currentDistanceMeters))
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                if let meters = value.as(Double.self) {
                    AxisValueLabel { Text(Self.distanceLabel(meters: meters)) }
                    AxisGridLine()
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                if let v = value.as(Double.self) {
                    AxisValueLabel { Text(yAxisLabel(for: v)) }
                    AxisGridLine()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard showCursor else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                displayMode = displayMode.next
            }
        }
        .onAppear { rebuild() }
        .onChange(of: route.id) { _, _ in rebuild() }
    }

    /// Segments fed to the chart. In normal mode this is the pre-decimated
    /// full-route cache; in zoomed mode it's built per-render from the
    /// undecimated points inside the visible window (~hundreds of points at
    /// 5m resampling, cheap to rebuild on each tick). If a completion
    /// cutoff is set, the result is post-processed to recolour everything
    /// past the cutoff in gray.
    private var displayedSegments: [RouteElevationSegment] {
        let base = displayMode == .elevationZoomed
            ? Self.buildSegments(from: zoomWindowPoints())
            : segments
        guard let cutoff = completedDistanceMeters else { return base }
        return Self.applyCompletionCutoff(base, cutoff: cutoff)
    }

    /// X-axis domain. Only `.elevationZoomed` constrains the window — the
    /// other modes show the full route (Charts auto-fits y separately).
    private var xDomain: ClosedRange<Double> {
        if displayMode == .elevationZoomed {
            let half = Self.zoomWindowMeters / 2
            return (currentDistanceMeters - half)...(currentDistanceMeters + half)
        }
        return 0...max(route.totalDistanceMeters, 1)
    }

    private func yAxisLabel(for value: Double) -> String {
        switch displayMode {
        case .gradeLine:
            return String(format: "%+.0f%%", value)
        case .elevation, .elevationZoomed:
            return Self.elevationLabel(meters: value)
        }
    }

    /// Undecimated route points whose distance falls inside the zoom window,
    /// plus one neighbour on each side so the AreaMark fills cleanly to the
    /// chart edges (the chart clips outside `xDomain` either way).
    private func zoomWindowPoints() -> [RoutePoint] {
        let all = route.points
        guard !all.isEmpty else { return [] }
        let half = Self.zoomWindowMeters / 2
        let lo = currentDistanceMeters - half
        let hi = currentDistanceMeters + half

        var loIdx = 0
        while loIdx + 1 < all.count, all[loIdx + 1].distanceMeters < lo {
            loIdx += 1
        }
        var hiIdx = all.count - 1
        while hiIdx > 0, all[hiIdx - 1].distanceMeters > hi {
            hiIdx -= 1
        }
        guard loIdx <= hiIdx else { return [] }
        return Array(all[loIdx...hiIdx])
    }

    private func rebuild() {
        let decimated = Self.decimate(route.points, maxRendered: Self.maxRenderedPoints)
        renderedPoints = decimated
        segments = Self.buildSegments(from: decimated)
    }

    /// Stride-sample a point array down to `maxRendered`, always retaining
    /// the last point so the chart's right edge reaches the route's end.
    static func decimate(_ points: [RoutePoint], maxRendered: Int) -> [RoutePoint] {
        guard points.count > maxRendered, maxRendered > 0 else { return points }
        let stride = Int(ceil(Double(points.count) / Double(maxRendered)))
        var sampled = Swift.stride(from: 0, to: points.count, by: stride).map { points[$0] }
        if sampled.last?.distanceMeters != points.last?.distanceMeters,
           let last = points.last {
            sampled.append(last)
        }
        return sampled
    }

    /// Walk pre-built segments and recolour any region past `cutoff` to
    /// gray. The segment that straddles the cutoff is split with an
    /// interpolated boundary point so the colour change lands on the
    /// exact distance instead of jumping to the next 5m resample step.
    static func applyCompletionCutoff(
        _ segments: [RouteElevationSegment],
        cutoff: Double
    ) -> [RouteElevationSegment] {
        let grayColour = Color.gray.opacity(0.35)
        var result: [RouteElevationSegment] = []
        result.reserveCapacity(segments.count + 1)

        for segment in segments {
            guard let firstD = segment.points.first?.distanceMeters,
                  let lastD = segment.points.last?.distanceMeters
            else { continue }

            if lastD <= cutoff {
                // Fully completed — keep the original colour.
                result.append(RouteElevationSegment(
                    id: result.count,
                    color: segment.color,
                    points: segment.points
                ))
            } else if firstD >= cutoff {
                // Entirely past the cutoff — gray it out.
                result.append(RouteElevationSegment(
                    id: result.count,
                    color: grayColour,
                    points: segment.points
                ))
            } else {
                // Cutoff lands inside this segment — split it into a
                // coloured front half and a gray tail.
                var before: [RoutePoint] = []
                var after: [RoutePoint] = []
                for point in segment.points {
                    if point.distanceMeters <= cutoff {
                        before.append(point)
                    } else {
                        after.append(point)
                    }
                }
                // Interpolate an exact-cutoff point so both halves end /
                // start on the same x — otherwise the chart shows a sliver
                // gap or a colour jump.
                if let last = before.last, let first = after.first,
                   last.distanceMeters < cutoff && first.distanceMeters > cutoff {
                    let span = first.distanceMeters - last.distanceMeters
                    let t = (cutoff - last.distanceMeters) / span
                    let interp = RoutePoint(
                        distanceMeters: cutoff,
                        elevationMeters: last.elevationMeters
                            + (first.elevationMeters - last.elevationMeters) * t,
                        gradePercent: last.gradePercent,
                        latitude: last.latitude,
                        longitude: last.longitude
                    )
                    before.append(interp)
                    after.insert(interp, at: 0)
                }
                if !before.isEmpty {
                    result.append(RouteElevationSegment(
                        id: result.count,
                        color: segment.color,
                        points: before
                    ))
                }
                if !after.isEmpty {
                    result.append(RouteElevationSegment(
                        id: result.count,
                        color: grayColour,
                        points: after
                    ))
                }
            }
        }
        return result
    }

    /// Split into consecutive runs of the same bucket. The transition point
    /// is included in BOTH the closing and the opening segment so the two
    /// adjacent areas meet visually instead of leaving a sliver gap.
    static func buildSegments(from points: [RoutePoint]) -> [RouteElevationSegment] {
        guard !points.isEmpty else { return [] }
        var result: [RouteElevationSegment] = []
        var current: [RoutePoint] = [points[0]]
        var currentBucket = gradeBucket(points[0].gradePercent)

        for i in 1..<points.count {
            let bucket = gradeBucket(points[i].gradePercent)
            if bucket != currentBucket {
                // Close out the current run with the transition point so the
                // outgoing colour reaches the boundary.
                current.append(points[i])
                result.append(RouteElevationSegment(
                    id: result.count,
                    color: bucketColor(currentBucket),
                    points: current
                ))
                // Start the new run at the transition point.
                current = [points[i]]
                currentBucket = bucket
            } else {
                current.append(points[i])
            }
        }
        result.append(RouteElevationSegment(
            id: result.count,
            color: bucketColor(currentBucket),
            points: current
        ))
        return result
    }

    static func gradeBucket(_ g: Double) -> String {
        switch g {
        case ..<(-1): return "Descent"
        case ..<1:    return "Flat"
        case ..<4:    return "Light"
        case ..<7:    return "Moderate"
        default:      return "Steep"
        }
    }

    static func gradeColor(_ g: Double) -> Color {
        bucketColor(gradeBucket(g))
    }

    private static func bucketColor(_ bucket: String) -> Color {
        switch bucket {
        case "Descent":  return .blue
        case "Flat":     return .green
        case "Light":    return .yellow
        case "Moderate": return .orange
        case "Steep":    return .red
        default:         return .gray
        }
    }

    private static func distanceLabel(meters: Double) -> String {
        UnitFormatting.distance(meters: meters)
    }

    private static func elevationLabel(meters: Double) -> String {
        if UnitFormatting.usesMetric {
            return "\(Int(meters)) m"
        } else {
            let ft = meters * 3.28084
            return "\(Int(ft)) ft"
        }
    }
}

/// One contiguous run of route points sharing the same grade-colour bucket.
/// Lifted out of `ElevationProfileView` so the share-card snapshot can reuse
/// the same segment-building pipeline.
struct RouteElevationSegment: Identifiable {
    let id: Int
    let color: Color
    let points: [RoutePoint]
}

private enum DisplayMode {
    case elevation
    case elevationZoomed
    case gradeLine

    var next: DisplayMode {
        switch self {
        case .elevation:       return .elevationZoomed
        case .elevationZoomed: return .gradeLine
        case .gradeLine:       return .elevation
        }
    }
}
