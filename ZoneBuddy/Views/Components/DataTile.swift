import SwiftUI

struct DataTile<Content: View>: View {
    let isVisible: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if isVisible {
            let cr: CGFloat = sizeClass == .regular ? 16 : 12
            content()
                .padding(sizeClass == .regular ? 16 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: cr)
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cr))
                }
        }
    }
}
