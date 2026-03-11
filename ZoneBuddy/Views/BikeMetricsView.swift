import SwiftUI
import FTMSKit

struct BikeMetricsView: View {
    let bikeData: BikeData?
    let isConnected: Bool
    let zoneColor: Color
    let foregroundColor: Color
    let avgPower: Int?
    let totalCalories: Int?

    var body: some View {
        VStack(spacing: 0) {
            if !isConnected {
                notConnectedState
            } else if let data = bikeData {
                metricsContent(data: data)
            } else {
                waitingState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricsContent(data: BikeData) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Primary metrics
            HStack(spacing: 32) {
                metricCard(
                    value: "\(data.instantaneousPower ?? 0)",
                    unit: "W",
                    label: "Power",
                    size: .large
                )
                metricCard(
                    value: "\(Int(data.instantaneousCadence ?? 0))",
                    unit: "rpm",
                    label: "Cadence",
                    size: .large
                )
            }

            // Secondary metrics
            HStack(spacing: 32) {
                if let hr = data.heartRate {
                    metricCard(
                        value: "\(hr)",
                        unit: "bpm",
                        label: "Heart Rate",
                        size: .medium
                    )
                }
                if let speed = data.instantaneousSpeed {
                    metricCard(
                        value: String(format: "%.1f", speed),
                        unit: "km/h",
                        label: "Speed",
                        size: .medium
                    )
                }
            }

            // Tertiary row
            HStack(spacing: 20) {
                if let dist = data.totalDistance {
                    miniMetric(
                        value: String(format: "%.2f", Double(dist) / 1000.0),
                        label: "Distance (km)"
                    )
                }
                if let cal = totalCalories ?? data.totalEnergy {
                    miniMetric(
                        value: "\(cal)",
                        label: "Calories"
                    )
                }
                if let avg = avgPower {
                    miniMetric(
                        value: "\(avg)",
                        label: "Avg Power"
                    )
                }
            }

            Spacer()
        }
        .padding()
    }

    private func metricCard(value: String, unit: String, label: String, size: MetricSize) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(size == .large
                          ? .system(size: 64, weight: .bold, design: .rounded)
                          : .system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(size == .large ? .title3 : .caption)
                    .fontWeight(.medium)
            }
            Text(label)
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1)
        }
        .foregroundStyle(foregroundColor)
    }

    private func miniMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .foregroundStyle(foregroundColor.opacity(0.8))
    }

    private var notConnectedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle")
                .font(.system(size: 60))
                .foregroundStyle(foregroundColor.opacity(0.4))
            Text("Bike Not Connected")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(foregroundColor.opacity(0.6))
            Text("Connect a bike in Settings")
                .font(.subheadline)
                .foregroundStyle(foregroundColor.opacity(0.4))
        }
    }

    private var waitingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(foregroundColor)
            Text("Waiting for data...")
                .font(.title3)
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
    }

    private enum MetricSize {
        case large, medium
    }
}
