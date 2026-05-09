import SwiftUI

struct OnboardingWhatIsThisView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            icon: "chart.bar.fill",
            title: "Train by Power Zones",
            subtitle: "Every workout is built around 7 zones, each a percentage of your FTP — the highest power you can hold for about an hour."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("ZoneBuddy guides you through interval workouts and reads live power from your bike to keep you on target.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    OnboardingBullet(text: "Zones 1–2: easy. Recovery and endurance.")
                    OnboardingBullet(text: "Zones 3–4: tempo and threshold. The hard, sustainable middle.")
                    OnboardingBullet(text: "Zones 5–7: VO₂, anaerobic, neuromuscular. Short bursts.")
                }
                .padding(.top, 4)

                Text("ZoneBuddy works best with an FTMS-compatible smart bike that streams live power. Without one, you can still build and follow workouts — but live power tracking and FTP-based zones won't be available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
            }
        } bottomBar: {
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

#Preview {
    OnboardingWhatIsThisView(onContinue: {})
        .preferredColorScheme(.dark)
}
