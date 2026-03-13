import SwiftUI

struct PowerMetricTile: View {
    let power: Int?
    let ftp: Int
    let foregroundColor: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(power.map { "\($0)" } ?? "--")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("W")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            if let power, ftp > 0 {
                Text("\(Int((Double(power) / Double(ftp)) * 100))% FTP")
                    .font(.caption2)
                    .foregroundStyle(foregroundColor.opacity(0.7))
            }
            Text("Power")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .foregroundStyle(foregroundColor)
    }
}

struct CadenceTile: View {
    let cadence: Double?
    let foregroundColor: Color

    var body: some View {
        MetricValueView(
            value: cadence.map { "\(Int($0))" } ?? "--",
            unit: "rpm",
            label: "Cadence",
            foregroundColor: foregroundColor
        )
    }
}

struct HeartRateTile: View {
    let heartRate: Int?
    let foregroundColor: Color

    var body: some View {
        MetricValueView(
            value: heartRate.map { "\($0)" } ?? "--",
            unit: "bpm",
            label: "Heart Rate",
            foregroundColor: foregroundColor
        )
    }
}

struct SpeedTile: View {
    let speed: Double? // km/h from bike
    let foregroundColor: Color

    private var usesMetric: Bool {
        Locale.current.measurementSystem != .us
    }

    private var displayValue: String {
        guard let speed else { return "--" }
        return usesMetric
            ? String(format: "%.1f", speed)
            : String(format: "%.1f", speed * 0.621371)
    }

    private var unit: String { usesMetric ? "km/h" : "mph" }

    var body: some View {
        MetricValueView(
            value: displayValue,
            unit: unit,
            label: "Speed",
            foregroundColor: foregroundColor
        )
    }
}

struct DistanceTile: View {
    let distance: Double? // meters
    let foregroundColor: Color

    private var usesMetric: Bool {
        Locale.current.measurementSystem != .us
    }

    private var displayValue: String {
        guard let distance else { return "--" }
        return usesMetric
            ? String(format: "%.2f", distance / 1000.0)
            : String(format: "%.2f", distance / 1609.344)
    }

    private var unit: String { usesMetric ? "km" : "mi" }

    var body: some View {
        MetricValueView(
            value: displayValue,
            unit: unit,
            label: "Distance",
            foregroundColor: foregroundColor
        )
    }
}

struct CaloriesTile: View {
    let calories: Int?
    let foregroundColor: Color

    var body: some View {
        MetricValueView(
            value: calories.map { "\($0)" } ?? "--",
            unit: "kcal",
            label: "Calories",
            foregroundColor: foregroundColor
        )
    }
}

struct AvgPowerTile: View {
    let avgPower: Int?
    let foregroundColor: Color

    var body: some View {
        MetricValueView(
            value: avgPower.map { "\($0)" } ?? "--",
            unit: "W",
            label: "Avg Power",
            foregroundColor: foregroundColor
        )
    }
}

struct OutputTile: View {
    let outputKJ: Double?
    let foregroundColor: Color

    var body: some View {
        MetricValueView(
            value: outputKJ.map { String(format: "%.0f", $0) } ?? "--",
            unit: "kJ",
            label: "Output",
            foregroundColor: foregroundColor
        )
    }
}

// MARK: - Shared metric layout

private struct MetricValueView: View {
    let value: String
    let unit: String
    let label: String
    let foregroundColor: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .foregroundStyle(foregroundColor)
    }
}
