import SwiftUI

struct OnboardingPrivacyView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            icon: "lock.shield",
            title: "Your data stays yours",
            subtitle: "ZoneBuddy is built around your privacy. There are no accounts and no third-party servers."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingBullet(text: "Workouts and history are stored on this device and synced through your iCloud account.")
                OnboardingBullet(text: "No analytics, no tracking, no third parties.")
                OnboardingBullet(text: "Health data only flows between ZoneBuddy and Apple's Health app — and only with your permission.")
                OnboardingBullet(text: "Export or delete anything, anytime.")
            }
        } bottomBar: {
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

#Preview {
    OnboardingPrivacyView(onContinue: {})
        .preferredColorScheme(.dark)
}
