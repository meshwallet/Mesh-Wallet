import SwiftUI

/// Three-line menu glyph for wallet home header (spacing tuned vs SF Symbol).
struct MeshHomeMenuIcon: View {
    var lineWidth: CGFloat = 22
    var lineHeight: CGFloat = 2.25
    var spacing: CGFloat = 6
    var color: Color = MeshTheme.Colors.homeChromeIcon

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(color)
                    .frame(width: lineWidth, height: lineHeight)
            }
        }
        .accessibilityHidden(true)
    }
}
