import SwiftUI

struct OnboardingDoneView: View {
    let onFinish: () -> Void

    @State private var animateBounce: Bool = false

    var body: some View {
        OnboardingStepScaffold(
            icon: "checkmark.circle.fill",
            title: "You're all set",
            subtitle: "Let's get you riding. You can change anything later from Settings."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingBullet(text: "Browse the workout library or generate one tailored to today.")
                OnboardingBullet(text: "Hop on the bike and start a session — ZoneBuddy handles the rest.")
                OnboardingBullet(text: "Need to change FTP, bike, or audio cues later? Settings has it all.")
            }
        } bottomBar: {
            OnboardingPrimaryButton(title: "Start Riding", action: onFinish)
        }
    }
}

#Preview {
    OnboardingDoneView(onFinish: {})
        .preferredColorScheme(.dark)
}
