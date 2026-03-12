import SwiftUI

struct WatchIntervalRowView: View {
    let interval: Interval
    let index: Int
    let currentIndex: Int
    let isCooldown: Bool

    private var isCompleted: Bool { index < currentIndex }
    private var isCurrent: Bool { index == currentIndex }

    private var label: String {
        if isCooldown { return "Cooldown" }
        return interval.baseLabel
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(interval.zone?.color ?? .gray)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(interval.duration.formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isCompleted {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isCurrent ? Color.gray.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
