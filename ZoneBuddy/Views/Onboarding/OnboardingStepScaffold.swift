import SwiftUI

/// Shared per-step layout for onboarding. Mirrors the structure used in `FTPTestIntroView`
/// (hero icon → title → subtitle → body content → bottom Liquid Glass capsule button)
/// so the visual language stays consistent with the rest of the app.
struct OnboardingStepScaffold<Content: View, BottomBar: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottomBar: () -> BottomBar

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder bottomBar: @escaping () -> BottomBar
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.bottomBar = bottomBar
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar()
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Pre-styled "Continue" capsule button used by most onboarding steps.
struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(!isEnabled)
    }
}

/// Secondary "Skip" / tertiary action — plain text-style button.
struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Bullet row used by privacy / power-zone explainer screens.
struct OnboardingBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.tint)
                .padding(.top, 7)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Thin progress indicator showing position within the onboarding flow.
struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.25))
                Capsule()
                    .fill(.tint)
                    .frame(width: geo.size.width * CGFloat(current) / CGFloat(max(total, 1)))
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
        .frame(height: 4)
    }
}
