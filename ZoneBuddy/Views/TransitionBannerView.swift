import SwiftUI

struct TransitionBannerView: View {
    let upcomingLabel: String
    let upcomingColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)

            Text("Up Next:")
                .font(.headline)

            Text(upcomingLabel)
                .font(.title2)
                .fontWeight(.bold)

            Circle()
                .fill(upcomingColor)
                .frame(width: 24, height: 24)
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
            TransitionBannerView(upcomingLabel: "Zone 5", upcomingColor: .orange)
                .padding(.bottom, 100)
        }
    }
}
