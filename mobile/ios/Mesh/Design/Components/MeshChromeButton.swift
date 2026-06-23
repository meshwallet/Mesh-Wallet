import SwiftUI

/// Circular chrome control — dark frosted glass disc (48pt).
struct MeshChromeButton: View {
    var systemImage: String = "xmark"
    var size: CGFloat = MeshTheme.Metrics.chromeButtonSize
    var appearance: Appearance = .chrome
    let action: () -> Void

    enum Appearance {
        case chrome
        case plain
    }

    private var usesLiquidGlass: Bool {
        appearance == .chrome && MeshLiquidGlass.isSupported
    }

    var body: some View {
        Group {
            if appearance == .chrome {
                Button(action: action, label: chromeLabel)
                    .buttonStyle(MeshGlassCircleButtonStyle())
            } else {
                Button(action: action, label: chromeLabel)
                    .buttonStyle(MeshChromePlainButtonStyle())
            }
        }
    }

    private func chromeLabel() -> some View {
        ZStack {
            if appearance == .chrome {
                MeshGlassCircleBackground(diameter: size, style: .chrome)
                    .meshLiquidGlassSurface(
                        enabled: usesLiquidGlass,
                        shape: .circle,
                        tint: MeshWalletHomeGlass.chromeDiscGlassTint
                    )
            }

            Image(systemName: systemImage)
                .font(MeshTheme.Typography.icon(size: 16, weight: .medium))
                .foregroundStyle(
                    appearance == .chrome
                        ? MeshTheme.Colors.textPrimary
                        : MeshTheme.Colors.textSecondary
                )
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

private struct MeshChromePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

extension MeshChromeButton {
    static func close(appearance: Appearance = .chrome, action: @escaping () -> Void) -> MeshChromeButton {
        MeshChromeButton(systemImage: "xmark", appearance: appearance, action: action)
    }

    static func back(appearance: Appearance = .chrome, action: @escaping () -> Void) -> MeshChromeButton {
        MeshChromeButton(systemImage: "chevron.left", appearance: appearance, action: action)
    }
}
