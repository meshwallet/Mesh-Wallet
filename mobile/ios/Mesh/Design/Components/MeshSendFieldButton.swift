import SwiftUI

/// Compact capsule action beside send fields (paste, scan, send to self).
struct MeshSendFieldButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    private let height: CGFloat = 34
    private let horizontalPadding: CGFloat = 12
    private let iconSize: CGFloat = 12

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(MeshTheme.Typography.icon(size: iconSize, weight: .medium))
                Text(title)
                    .font(MeshTheme.Typography.sans(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(MeshTheme.Colors.textSecondary)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(
                MeshTheme.Colors.fieldFill.opacity(0.55),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(MeshTheme.Colors.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
