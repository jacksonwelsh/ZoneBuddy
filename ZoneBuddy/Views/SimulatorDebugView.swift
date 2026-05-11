#if DEBUG
import SwiftUI

/// DEBUG-only Settings section that drives `SimulatorFakes` state and exposes
/// shims for simulating Watch-sent WCSession messages without a paired Watch.
/// Hidden unless fakes are active (env var or runtime toggle).
struct SimulatorDebugView: View {
    @Bindable var fakes = SimulatorFakes.shared

    var body: some View {
        Group {
            if fakes.isEnabled {
                activeSection
            } else {
                inactiveSection
            }
        }
    }

    private var activeSection: some View {
        Group {
            Section {
                LabeledContent("Mode") {
                    Text(fakes.envVarSet ? "Env var" : "Runtime")
                        .foregroundStyle(.secondary)
                }
                if !fakes.envVarSet {
                    Toggle("Fakes Enabled", isOn: $fakes.userToggleEnabled)
                }
                Toggle("Bike Connected", isOn: $fakes.bikeConnected)
                Toggle("Skip HealthKit Writes", isOn: $fakes.preventHealthKitWrite)
            } header: {
                Text("Simulator")
            } footer: {
                Text("Debug-only. Time-varying fake bike + heart-rate data driven by the controls below.")
            }

            Section("Target Power") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(fakes.targetPower) W")
                            .font(.title3.monospacedDigit())
                        Spacer()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(fakes.targetPower) },
                            set: { fakes.targetPower = Int($0) }
                        ),
                        in: 0...500,
                        step: 5
                    )
                    HStack(spacing: 8) {
                        ForEach([("Rec", 80), ("Z2", 150), ("Z4", 220), ("Z5", 280)], id: \.1) { label, watts in
                            Button(label) { fakes.targetPower = watts }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }

            Section("Heart Rate Override") {
                Toggle("Override Enabled", isOn: Binding(
                    get: { fakes.hrOverride != nil },
                    set: { enabled in fakes.hrOverride = enabled ? 130 : nil }
                ))
                if let _ = fakes.hrOverride {
                    Stepper(
                        "\(fakes.hrOverride ?? 0) bpm",
                        value: Binding(
                            get: { fakes.hrOverride ?? 130 },
                            set: { fakes.hrOverride = $0 }
                        ),
                        in: 50...200
                    )
                }
            }

            Section {
                // Fires both the WCSession (iPhone) and BLE (iPad) inbound paths
                // so the buttons work on whichever transport the active device uses.
                Button("Pause") {
                    WorkoutConnectivityManager.shared.debugSimulatePauseFromWatch()
                    BLEHeartRateScanner.shared.debugSimulatePauseFromWatch()
                }
                Button("Resume") {
                    WorkoutConnectivityManager.shared.debugSimulateResumeFromWatch()
                    BLEHeartRateScanner.shared.debugSimulateResumeFromWatch()
                }
                Button("End") {
                    WorkoutConnectivityManager.shared.debugSimulateEndFromWatch()
                    BLEHeartRateScanner.shared.debugSimulateEndFromWatch()
                }
                Button("HR = 145") {
                    WorkoutConnectivityManager.shared.debugSimulateInboundHR(145)
                    BLEHeartRateScanner.shared.debugSimulateInboundHR(145)
                }
            } header: {
                Text("Simulate Watch Sent")
            } footer: {
                Text("Fires both WCSession (iPhone) and BLE (iPad) inbound handlers.")
            }
        }
    }

    private var inactiveSection: some View {
        Section {
            Toggle("Enable Simulator Fakes", isOn: $fakes.userToggleEnabled)
        } header: {
            Text("Simulator")
        } footer: {
            Text("Debug-only. Replaces the real Bluetooth bike + Watch HR with on-device fakes for testing in the simulator.")
        }
    }
}
#endif
