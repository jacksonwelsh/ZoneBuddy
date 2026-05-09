import SwiftUI

struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            icon: "figure.indoor.cycle",
            title: "Welcome to ZoneBuddy",
            subtitle: "Power-zone training for your indoor bike."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("ZoneBuddy turns your indoor rides into structured workouts that match your fitness — guided intervals, live power tracking, and audio cues so you know exactly when to push and when to recover.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } bottomBar: {
            OnboardingPrimaryButton(title: "Get Started", action: onContinue)
        }
    }
}

#Preview {
    OnboardingWelcomeView(onContinue: {})
        .preferredColorScheme(.dark)
}
