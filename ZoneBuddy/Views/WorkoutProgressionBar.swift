import SwiftUI

struct WorkoutProgressionBar: View {
    let intervals: [Interval]
    let totalDuration: Int

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if totalDuration > 0 {
                    ForEach(intervals.sorted(by: { $0.sortOrder < $1.sortOrder })) { interval in
                        Rectangle()
                            .fill(interval.zone?.color ?? Color.gray)
                            .frame(width: geometry.size.width * CGFloat(interval.duration) / CGFloat(totalDuration))
                    }
                } else {
                    Color.clear
                }
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
    }
}

#Preview {
    WorkoutProgressionBar(
        intervals: [
            Interval(zone: .zone2, duration: 300, sortOrder: 0),
            Interval(zone: .zone3, duration: 300, sortOrder: 1),
            Interval(zone: .zone4, duration: 120, sortOrder: 2),
            Interval(zone: .zone1, duration: 180, sortOrder: 3)
        ],
        totalDuration: 900
    )
    .padding()
}
