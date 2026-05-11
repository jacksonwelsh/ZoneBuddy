import SwiftUI

struct OnboardingBluetoothPermissionView: View {
    var bikeManager: any BikeConnecting = BikeManagerProvider.current
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            icon: "antenna.radiowaves.left.and.right",
            title: "Find your bike",
            subtitle: "ZoneBuddy needs Bluetooth permission to discover and connect to your smart bike."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingBullet(text: "Used only to talk to FTMS-compatible bikes and to relay heart rate from your Apple Watch.")
                OnboardingBullet(text: "No data is ever sent over the internet from this connection.")
                OnboardingBullet(text: "iOS will ask for permission when you tap Continue.")
            }
        } bottomBar: {
            OnboardingPrimaryButton(title: "Continue", action: {
                bikeManager.startScanning()
                onContinue()
            })
        }
    }
}

#Preview {
    OnboardingBluetoothPermissionView(onContinue: {})
        .preferredColorScheme(.dark)
}
