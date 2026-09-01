import SwiftUI

struct CycloneSettingsSection: View {
    @State private var service = CycloneService.shared
    @State private var server = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if service.isConnected {
                LabeledContent("Server", value: service.serverName ?? "Connected")
                Button("Remove Cyclone enrollment", role: .destructive) {
                    service.disconnect()
                }
            } else {
                TextField("https://cyclone.example.com/v1", text: $server)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Single-use enrollment code", text: $code)
                    .textInputAutocapitalization(.never)
                    .privacySensitive()
                Button {
                    Task { await enroll() }
                } label: {
                    if isWorking { ProgressView() }
                    else { Label("Enroll with Cyclone", systemImage: "link") }
                }
                .disabled(server.isEmpty || code.isEmpty || isWorking)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Cyclone")
        } footer: {
            Text("Cyclone export creates a private draft and opens it for editing. It is independent of Strava and never publishes automatically.")
        }
    }

    private func enroll() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.enroll(server: server, code: code, deviceName: UIDevice.current.name)
            code = ""
        } catch let error as CycloneError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
