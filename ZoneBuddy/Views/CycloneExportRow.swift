import SwiftUI

struct CycloneExportRow: View {
    let session: WorkoutSession
    @State private var service = CycloneService.shared

    var body: some View {
        if service.isConnected && session.canExportToCyclone {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Cyclone", systemImage: "wind")
                        .font(.headline)
                    Spacer()
                    statusBadge
                }
                content
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.cycloneExportState {
        case .exported:
            if let id = session.cycloneActivityID {
                Button {
                    Task { await service.openDraft(id) }
                } label: {
                    Label("Open Draft in Cyclone", systemImage: "arrow.up.right.square")
                }
            }
        case .exporting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Creating draft…").foregroundStyle(.secondary)
            }
        case .failed:
            if let error = session.cycloneExportError {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
            }
            exportButton("Retry Export")
        case .notExported:
            exportButton("Export to Cyclone")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.cycloneExportState {
        case .exported:
            Label("Draft created", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private func exportButton(_ title: String) -> some View {
        Button {
            Task { await service.export(session) }
        } label: {
            Label(title, systemImage: "arrow.up.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)
    }
}
