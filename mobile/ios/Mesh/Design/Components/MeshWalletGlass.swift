import SwiftUI

// MARK: - Wallet home glass palette (mockup-aligned)

enum MeshWalletHomeGlass {
    /// iOS 26 liquid glass — send / receive (light, transparent).
    static let discGlassTint = Color.white.opacity(0.07)
    /// iOS 26 liquid glass — close / back chrome (darker).
    static let chromeDiscGlassTint = Color.black.opacity(0.52)
    /// iOS 26 liquid glass — translucent purple fund CTA.
    static let fundGlassTint = Color(hex: 0x9B8AD8).opacity(0.40)
    /// Solid fill for Fund CTA (no gradient).
    static let fundFill = Color(hex: 0x7A6AB8).opacity(0.52)
    static let fundGlow = Color(hex: 0xA18DCA).opacity(0.22)
    /// iOS 26 liquid glass — compact wallet action popover.
    static let menuGlassTint = Color.white.opacity(0.11)
}

// MARK: - Frosted fallbacks (pre–Liquid Glass)

/// Frosted glass disc — wallet home actions and chrome close/back.
struct MeshGlassCircleBackground: View {
    enum Style {
        case action
        case chrome
    }

    var diameter: CGFloat = MeshTheme.Metrics.circleButtonSize
    var style: Style = .action

    private var baseFill: Color {
        style == .chrome
            ? Color.black.opacity(0.32)
            : Color.white.opacity(0.02)
    }

    private var highlightTop: CGFloat {
        style == .chrome ? 0.04 : 0.05
    }

    private var highlightMid: CGFloat {
        style == .chrome ? 0.01 : 0.01
    }

    private var strokeLeading: CGFloat {
        style == .chrome ? 0.14 : 0.12
    }

    private var strokeTrailing: CGFloat {
        style == .chrome ? 0.05 : 0.05
    }

    var body: some View {
        Circle()
            .fill(baseFill)
            .background {
                Circle()
                    .fill(style == .chrome ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.thinMaterial.opacity(0.55)))
            }
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(highlightTop),
                                Color.white.opacity(highlightMid),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.28, y: 0.22),
                            startRadius: 0,
                            endRadius: diameter * 0.85
                        )
                    )
            }
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strokeLeading),
                                Color.white.opacity(strokeTrailing),
                                Color.white.opacity(strokeLeading * 0.65),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: style == .chrome ? 0.5 : 1
                    )
            }
            .frame(width: diameter, height: diameter)
    }
}

/// Purple primary CTA capsule — Fund, Next, Continue, etc.
struct MeshGlassCapsuleBackground: View {
    var body: some View {
        Capsule()
            .fill(MeshWalletHomeGlass.fundFill)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.05),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: MeshWalletHomeGlass.fundGlow, radius: 12, y: 6)
            .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
    }
}

/// Accounts drawer — same Liquid Glass chrome as `MeshWalletTabBar`.
struct MeshAccountsDrawerGlassBackground: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background {
                if !MeshLiquidGlass.isSupported {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if !MeshLiquidGlass.isSupported {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(MeshTheme.Colors.borderSubtle, lineWidth: 1)
                }
            }
            .meshLiquidGlassSurface(
                enabled: MeshLiquidGlass.isSupported,
                shape: .roundedRectangle(radius: cornerRadius)
            )
    }
}

/// Light popover panel for wallet row ⋯ menus (white, no accent tint).
struct MeshLightPopoverBackground: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            }
    }
}

/// Frosted / Liquid Glass panel for wallet row ⋯ menus (popover).
struct MeshGlassPopoverBackground: View {
    var cornerRadius: CGFloat = 14

    private var usesLiquidGlass: Bool { MeshLiquidGlass.isSupported }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.30))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.02),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.32, y: 0.18),
                            startRadius: 0,
                            endRadius: 160
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.14),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .meshLiquidGlassSurface(
                enabled: usesLiquidGlass,
                shape: .roundedRectangle(radius: cornerRadius),
                tint: MeshWalletHomeGlass.menuGlassTint
            )
    }
}

struct MeshGlassMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct MeshLightMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                }
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// White SF Symbol + title for native `Menu` rows on dark UI.
struct MeshContextMenuLabel: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(MeshTheme.Typography.icon(size: 16, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isDestructive ? Color.red : Color.white)
            Text(title)
                .foregroundStyle(Color.white)
        }
    }
}

// MARK: - Wallet home actions

struct MeshWalletFundButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        MeshPrimaryButton(
            title: title,
            titleColor: MeshTheme.Colors.homeTextPrimary,
            action: action
        )
    }
}

struct MeshWalletCircleActionButton: View {
    let icon: String
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    private var circleSize: CGFloat { MeshTheme.Metrics.circleButtonSize }

    private var usesLiquidGlass: Bool {
        MeshLiquidGlass.isSupported
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: action) {
                ZStack {
                    MeshGlassCircleBackground(diameter: circleSize, style: .action)
                        .meshLiquidGlassSurface(
                            enabled: usesLiquidGlass && isEnabled,
                            shape: .circle,
                            tint: MeshWalletHomeGlass.discGlassTint
                        )

                    Image(systemName: icon)
                        .font(MeshTheme.Typography.icon(size: 26, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.homeTextPrimary)
                }
                .frame(width: circleSize, height: circleSize)
                .contentShape(Circle())
            }
            .buttonStyle(MeshGlassCircleButtonStyle())

            Text(title)
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.homeTextPrimary)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.25), value: isEnabled)
    }
}

struct MeshGlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
