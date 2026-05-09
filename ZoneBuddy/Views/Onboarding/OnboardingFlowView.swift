import SwiftUI

/// Root container for the first-launch onboarding flow. Shown via `.fullScreenCover`
/// over the main `TabView` until the user finishes (or until they re-trigger via the
/// iOS Settings.app toggle).
struct OnboardingFlowView: View {
    /// Called when onboarding completes (success or skipped-to-end). Receives a bool
    /// indicating whether the host should immediately push the FTP test flow.
    let onDismiss: (_ routeToFTPTest: Bool) -> Void

    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(viewModel.currentStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .animation(.easeInOut(duration: 0.28), value: viewModel.currentStep)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(viewModel.canGoBack ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoBack)

            OnboardingProgressBar(current: viewModel.progress.current, total: viewModel.progress.total)

            Text("\(viewModel.progress.current) / \(viewModel.progress.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch viewModel.currentStep {
        case .welcome:
            OnboardingWelcomeView(onContinue: viewModel.advance)
        case .whatIsThis:
            OnboardingWhatIsThisView(onContinue: viewModel.advance)
        case .privacy:
            OnboardingPrivacyView(onContinue: viewModel.advance)
        case .bikeQuestion:
            OnboardingBikeQuestionView(viewModel: viewModel, onContinue: viewModel.advance)
        case .bluetooth:
            OnboardingBluetoothPermissionView(onContinue: viewModel.advance)
        case .bikeConnect:
            OnboardingBikeConnectView(onContinue: viewModel.advance)
        case .watchHR:
            OnboardingWatchHRView(onContinue: viewModel.advance)
        case .ftp:
            OnboardingFTPView(viewModel: viewModel, onContinue: viewModel.advance)
        case .done:
            OnboardingDoneView(onFinish: finish)
        }
    }

    private func finish() {
        viewModel.finalize()
        onDismiss(viewModel.routeToFTPTestAfterDismiss)
    }
}

#Preview {
    OnboardingFlowView(onDismiss: { _ in })
}
