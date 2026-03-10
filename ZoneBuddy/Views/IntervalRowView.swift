import SwiftUI

struct IntervalRowView: View {
    let interval: Interval
    let isCooldown: Bool

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(interval.zone?.color ?? Color.gray)
                .frame(width: 8)

            VStack(alignment: .leading) {
                Text(label)
                    .font(.headline)
                Text(interval.duration.formattedDuration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(interval.duration.formattedDuration)")
    }

    private var label: String {
        if interval.isWarmup { return "Warmup" }
        if isCooldown { return "Cooldown" }
        return interval.zone?.zoneName ?? "Unknown"
    }
}

#Preview {
    List {
        IntervalRowView(interval: .warmup(duration: 300, sortOrder: 0), isCooldown: false)
        IntervalRowView(interval: Interval(zone: .zone3, duration: 300, sortOrder: 1), isCooldown: false)
        IntervalRowView(interval: Interval(zone: .zone5, duration: 120, sortOrder: 2), isCooldown: false)
        IntervalRowView(interval: Interval(zone: .zone1, duration: 180, sortOrder: 3), isCooldown: true)
    }
}
