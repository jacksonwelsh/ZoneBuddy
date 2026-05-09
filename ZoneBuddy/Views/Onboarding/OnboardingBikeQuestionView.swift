import SwiftUI

struct OnboardingBikeQuestionView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    @State private var showExamples: Bool = false

    var body: some View {
        OnboardingStepScaffold(
            icon: "bicycle",
            title: "Do you have a smart bike?",
            subtitle: "ZoneBuddy reads live power from any bike that supports the standard FTMS Bluetooth profile."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                answerButton(.yes, label: "Yes, I have one", systemImage: "checkmark.circle.fill")
                answerButton(.no, label: "No, not right now", systemImage: "xmark.circle")
                answerButton(.notSure, label: "Not sure — show me examples", systemImage: "questionmark.circle")

                if showExamples || viewModel.bikeAnswer == .notSure {
                    examplesBlock
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showExamples)
            .animation(.easeInOut(duration: 0.2), value: viewModel.bikeAnswer)
        } bottomBar: {
            OnboardingPrimaryButton(
                title: "Continue",
                action: onContinue,
                isEnabled: viewModel.bikeAnswer != nil
            )
        }
    }

    private func answerButton(_ answer: BikeAnswer, label: String, systemImage: String) -> some View {
        let isSelected = viewModel.bikeAnswer == answer
        return Button {
            viewModel.bikeAnswer = answer
            viewModel.recomputePath()
            if answer == .notSure {
                showExamples = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 28)
                Text(label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    private var examplesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bikes & trainers that work with ZoneBuddy")
                .font(.subheadline.weight(.semibold))
            Text("Peloton Bike+, Wahoo Kickr, Concept2 BikeErg, Schwinn IC4, and many other FTMS-compatible bikes and trainers. If your bike pairs with apps like Zwift over Bluetooth, it likely works here too.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            Text("ZoneBuddy is not affiliated with, endorsed by, or sponsored by Peloton Interactive, Inc., Wahoo Fitness, or any other manufacturer. Trademarks belong to their respective owners. ZoneBuddy works with any bike that supports the standard FTMS Bluetooth profile.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 6)
    }
}

#Preview {
    OnboardingBikeQuestionView(viewModel: OnboardingViewModel(), onContinue: {})
        .preferredColorScheme(.dark)
}
