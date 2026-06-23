import SwiftUI

/// Welcome — circular action (icon in disc + label below).
struct MeshWelcomeCircleButton: View {
    enum Kind {
        case create
        case restore
    }

    let kind: Kind
    var size: CGFloat = MeshTheme.Metrics.welcomeCircleButtonSize
    let action: () -> Void

    private var usesLiquidGlass: Bool { MeshLiquidGlass.isSupported }

    private var icon: String {
        switch kind {
        case .create: "plus"
        case .restore: "arrow.triangle.2.circlepath"
        }
    }

    private var title: String {
        switch kind {
        case .create: "Create"
        case .restore: "Restore"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    if !usesLiquidGlass {
                        Circle()
                            .fill(circleFill)

                        if kind == .restore {
                            Circle()
                                .stroke(MeshTheme.Colors.border, lineWidth: 1)
                        }
                    }

                    Image(systemName: icon)
                        .font(MeshTheme.Typography.icon(size: size * 0.34, weight: .light))
                        .foregroundStyle(iconColor)
                }
                .frame(width: size, height: size)
                .meshLiquidGlassSurface(
                    enabled: usesLiquidGlass,
                    shape: .circle,
                    tint: kind == .create ? MeshTheme.Colors.accent : nil
                )

                Text(title)
                    .font(MeshTheme.Typography.sans(size: 16, weight: .light))
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MeshWelcomeCircleButtonStyle())
    }

    private var circleFill: Color {
        switch kind {
        case .create:
            return MeshTheme.Colors.accent
        case .restore:
            return MeshTheme.Colors.fieldFill
        }
    }

    private var iconColor: Color {
        switch kind {
        case .create:
            return MeshTheme.Colors.buttonPrimaryText
        case .restore:
            return MeshTheme.Colors.textPrimary
        }
    }
}

private struct MeshWelcomeCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
