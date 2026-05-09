import SwiftUI

struct OnboardingWatchHRView: View {
    let onContinue: () -> Void

    @State private var requesting: Bool = false
    @State private var didRequest: Bool = false

    var body: some View {
        OnboardingStepScaffold(
            icon: "applewatch.radiowaves.left.and.right",
            title: "Heart rate, your way",
            subtitle: "ZoneBuddy can show your heart rate during workouts and save sessions to the Health app."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingBullet(text: "Wear an Apple Watch — install the ZoneBuddy Watch app for live HR during rides.")
                    OnboardingBullet(text: "Or use any Bluetooth heart rate monitor (chest strap, AirPods Pro with HR, etc.).")
                    OnboardingBullet(text: "Without an HR source, everything else still works — just no heart rate display.")
                }

                Text("Tap Allow Health Access to grant ZoneBuddy permission to read heart rate and save your workouts to the Health app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        } bottomBar: {
            VStack(spacing: 6) {
                OnboardingPrimaryButton(
                    title: didRequest ? "Continue" : "Allow Health Access",
                    action: {
                        if didRequest {
                            onContinue()
                        } else {
                            requestHealthAccess()
                        }
                    },
                    isEnabled: !requesting
                )
                if !didRequest {
                    OnboardingSecondaryButton(title: "Skip for now", action: onContinue)
                }
            }
        }
    }

    private func requestHealthAccess() {
        requesting = true
        Task {
            _ = await LiveHealthKitWorkoutManager().requestAuthorization()
            requesting = false
            didRequest = true
        }
    }
}

#Preview {
    OnboardingWatchHRView(onContinue: {})
        .preferredColorScheme(.dark)
}
