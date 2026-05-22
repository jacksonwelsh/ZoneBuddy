import SwiftUI

/// Headline route-mode block shown on the active page of the player.
/// Renders the elevation profile with a moving position cursor, plus
/// a row of distance/gain/grade tiles. Shared between iPhone & iPad.
struct RouteOverviewBlock: View {
    var routeController: RouteProgressionController
    var fgColor: Color = .white

    var body: some View {
        VStack(spacing: 12) {
            ElevationProfileView(
                route: routeController.route,
                currentDistanceMeters: routeController.distanceMeters
            )
            .frame(maxWidth: .infinity)
            .frame(height: 140)

            HStack(spacing: 12) {
                routeStatTile(
                    value: distanceLabel,
                    caption: "DISTANCE",
                    color: fgColor
                )
                routeStatTile(
                    value: gainLabel,
                    caption: "ELEV. GAIN",
                    color: fgColor
                )
                routeStatTile(
                    value: gradeLabel,
                    caption: "GRADE",
                    color: ElevationProfileView.gradeColor(routeController.currentGradePercent)
                )
            }
        }
    }

    @ViewBuilder
    private func routeStatTile(value: String, caption: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2)
                .tracking(0.5)
                .foregroundStyle(fgColor.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private var distanceLabel: String {
        let done = UnitFormatting.distance(meters: routeController.distanceMeters)
        let total = UnitFormatting.distance(meters: routeController.route.totalDistanceMeters)
        return "\(done)/\(total) \(UnitFormatting.distanceUnit)"
    }

    private var gainLabel: String {
        if UnitFormatting.usesMetric {
            return "\(Int(routeController.elevationGainMeters)) m"
        } else {
            return "\(Int(routeController.elevationGainMeters * 3.28084)) ft"
        }
    }

    private var gradeLabel: String {
        String(format: "%+.1f%%", routeController.currentGradePercent)
    }
}
