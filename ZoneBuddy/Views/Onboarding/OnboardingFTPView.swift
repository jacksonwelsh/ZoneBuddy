import SwiftUI

struct OnboardingFTPView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    @State private var ftpText: String = ""
    @FocusState private var ftpFocused: Bool

    var body: some View {
        OnboardingStepScaffold(
            icon: "bolt.fill",
            title: "Set your FTP",
            subtitle: "Functional Threshold Power — the highest power you can hold for about an hour. It anchors every zone."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ftpField

                Text("Don't know yours yet? 200W is a reasonable starting point. You can fine-tune it anytime in Settings, or run the 45-minute FTP test below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    saveFTP()
                    viewModel.routeToFTPTestAfterDismiss = true
                    onContinue()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "stopwatch")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Take FTP Test Now")
                                .font(.body.weight(.semibold))
                            Text("45 minutes — finish onboarding and start the test.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            }
        } bottomBar: {
            VStack(spacing: 6) {
                OnboardingPrimaryButton(title: "Save & Continue", action: {
                    saveFTP()
                    onContinue()
                })
                OnboardingSecondaryButton(title: "I'll do it later — keep \(viewModel.ftpInput)W", action: {
                    saveFTP()
                    onContinue()
                })
            }
        }
        .onAppear {
            ftpText = "\(viewModel.ftpInput)"
        }
    }

    private var ftpField: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text("FTP")
                .font(.body.weight(.medium))
            Spacer()
            TextField("200", text: $ftpText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($ftpFocused)
                .onChange(of: ftpText) { _, newValue in
                    if let value = Int(newValue), (50...500).contains(value) {
                        viewModel.ftpInput = value
                    }
                }
            Text("W")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func saveFTP() {
        if let value = Int(ftpText), (50...500).contains(value) {
            viewModel.ftpInput = value
        }
    }
}

#Preview {
    OnboardingFTPView(viewModel: OnboardingViewModel(), onContinue: {})
        .preferredColorScheme(.dark)
}
