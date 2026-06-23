import SwiftUI

struct MeshCard<Content: View>: View {
    var padding: CGFloat = MeshTheme.Metrics.cardPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .meshGlassPanel()
    }
}
