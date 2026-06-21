import SwiftUI

/// Strava upload control + status for a single session, shown on the workout
/// detail screen. Reflects the session's `stravaUploadState` and offers the
/// manual upload / retry action (the path for riders who keep auto-upload off,
/// or whose auto-upload failed).
struct StravaUploadRow: View {
    let session: WorkoutSession
    var service = StravaService.shared

    var body: some View {
        // Nothing to show for a disconnected account or a legacy ride with no
        // captured data — keep the detail screen uncluttered.
        if service.isConnected && session.canUploadToStrava {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Strava", systemImage: "figure.outdoor.cycle")
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
        switch session.stravaUploadState {
        case .uploaded:
            if let id = session.stravaActivityID {
                Link(destination: StravaConfig.activityURL(id: id)) {
                    Label("View on Strava", systemImage: "arrow.up.right.square")
                }
            }
        case .uploading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Uploading…").foregroundStyle(.secondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                if let error = session.stravaUploadError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                uploadButton(title: "Retry Upload")
            }
        case .notUploaded:
            uploadButton(title: "Upload to Strava")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.stravaUploadState {
        case .uploaded:
            Label("Uploaded", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private func uploadButton(title: String) -> some View {
        Button {
            Task { await service.upload(session) }
        } label: {
            Label(title, systemImage: "arrow.up.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
    }
}
