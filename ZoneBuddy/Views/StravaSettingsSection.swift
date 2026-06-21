import SwiftUI

/// Settings section for connecting a Strava account and controlling automatic
/// uploads. Pulled out of `SettingsView` to keep that view readable.
///
/// Note: for App Store distribution, Strava's brand guidelines require the
/// official "Connect with Strava" button artwork and a "Powered by Strava"
/// mark. This uses SF Symbols as a functional placeholder — swap in the brand
/// assets before shipping.
struct StravaSettingsSection: View {
    @Bindable var settings = SettingsManager.shared
    var service = StravaService.shared

    @State private var isConnecting = false
    @State private var connectError: String?

    var body: some View {
        Section {
            if service.isConnected {
                HStack {
                    Label("Account", systemImage: "person.crop.circle.badge.checkmark")
                    Spacer()
                    Text(service.athleteName ?? "Connected")
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $settings.stravaAutoUpload) {
                    Label("Auto-Upload Rides", systemImage: "arrow.up.circle.fill")
                }

                if settings.stravaAutoUpload {
                    Toggle(isOn: $settings.stravaAutoUploadIncludesFTPTests) {
                        Label("Include FTP Tests", systemImage: "stopwatch")
                    }
                }

                Button(role: .destructive) {
                    service.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "minus.circle")
                }
            } else {
                Button {
                    connect()
                } label: {
                    HStack {
                        Label("Connect with Strava", systemImage: "link")
                        if isConnecting {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isConnecting)
            }
        } header: {
            Text("Strava")
        } footer: {
            Text(footerText)
        }
        .alert("Couldn't Connect", isPresented: Binding(
            get: { connectError != nil },
            set: { if !$0 { connectError = nil } }
        )) {
            Button("OK", role: .cancel) { connectError = nil }
        } message: {
            Text(connectError ?? "")
        }
    }

    private var footerText: String {
        if service.isConnected {
            return settings.stravaAutoUpload
                ? "Completed rides upload automatically. You can still upload any ride manually from its entry in History."
                : "Auto-upload is off — upload each ride from its entry in History when you're ready."
        }
        return "Connect your Strava account to upload rides. Route rides are tagged as virtual rides with their map, just like Zwift."
    }

    private func connect() {
        isConnecting = true
        connectError = nil
        Task {
            do {
                try await service.connect()
            } catch let error as StravaError {
                connectError = error.userMessage
            } catch {
                // ASWebAuthenticationSession reports user cancellation as an
                // error; treat a plain cancel as a no-op rather than an alert.
                if (error as NSError).domain != "com.apple.AuthenticationServices.WebAuthenticationSession" {
                    connectError = error.localizedDescription
                }
            }
            isConnecting = false
        }
    }
}
