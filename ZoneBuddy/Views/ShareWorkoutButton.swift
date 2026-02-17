import SwiftUI
import LinkPresentation

final class WorkoutShareSource: NSObject, UIActivityItemSource {
    let url: URL
    let workoutName: String
    let subtitle: String

    init(url: URL, workoutName: String, intervalCount: Int, totalDuration: Int) {
        self.url = url
        self.workoutName = workoutName
        self.subtitle = "\(intervalCount) intervals \u{2022} \(totalDuration.formattedDuration)"
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = workoutName
        if let iconPath = Bundle.main.path(forResource: "zone-buddy-icon60x60@2x", ofType: "png"),
           let icon = UIImage(contentsOfFile: iconPath) {
            metadata.iconProvider = NSItemProvider(object: icon)
        }
        return metadata
    }
}

struct ShareWorkoutButton: View {
    let workout: Workout

    var body: some View {
        Button {
            share()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func share() {
        guard let url = try? WorkoutCoder.encode(workout) else { return }
        let source = WorkoutShareSource(
            url: url,
            workoutName: workout.name,
            intervalCount: workout.sortedIntervals.count,
            totalDuration: workout.totalDuration
        )
        let activityVC = UIActivityViewController(activityItems: [source], applicationActivities: nil)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.keyWindow?.rootViewController else { return }

        // Find the topmost presented controller
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
    }
}
