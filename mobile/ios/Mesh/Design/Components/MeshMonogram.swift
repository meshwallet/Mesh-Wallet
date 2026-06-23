import SwiftUI

/// Static brand mark — outline only, no gray fill.
struct MeshMonogram: View {
    var size: CGFloat = MeshTheme.Metrics.monogramSize

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .stroke(MeshTheme.Colors.border, lineWidth: 1)
            .frame(width: size, height: size)
            .overlay {
                Text("M")
                    .font(MeshTheme.Typography.sans(size: size * 0.38, weight: .light))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
            }
    }
}
