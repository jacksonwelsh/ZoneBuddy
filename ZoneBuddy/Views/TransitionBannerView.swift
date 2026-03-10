import SwiftUI

struct TransitionBannerView: View {
    let upcomingLabel: String
    let upcomingColor: Color
    let upcomingZoneNumber: Int?
    let upcomingForegroundColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)

            Text("Up Next:")
                .font(.headline)

            Text(upcomingLabel)
                .font(.title2)
                .fontWeight(.bold)

            if let number = upcomingZoneNumber {
                ZStack {
                    Circle()
                        .fill(upcomingColor)
                        .frame(width: 34, height: 34)
                    Text("\(number)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(upcomingForegroundColor)
                }
            } else {
                Circle()
                    .fill(upcomingColor)
                    .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .capsule)
        .foregroundStyle(.primary)
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        VStack {
            Spacer()
            TransitionBannerView(upcomingLabel: "VO2 Max", upcomingColor: .orange, upcomingZoneNumber: 5, upcomingForegroundColor: .black)
                .padding(.bottom, 100)
        }
    }
}
