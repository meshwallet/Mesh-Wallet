import SwiftUI

enum MeshTheme {
    enum Colors {
        static let background = Color.black
        static let backgroundElevated = Color(hex: 0x141414)
        static let surface = Color(hex: 0x1C1C1E)
        static let surfaceElevated = Color(hex: 0x2C2C2E)
        static let surfacePressed = Color(hex: 0x3A3A3C)

        /// Primary accent — lavender (#A18DCA). Wallet home hero backdrop stays separate (see MeshWalletHomeColors).
        static let accent = Color(hex: 0xA18DCA)
        static let accentPressed = Color(hex: 0x8B76B3)
        static let accentMuted = Color(hex: 0xA18DCA).opacity(0.35)

        /// Close / chrome circle on black.
        static let chromeFill = Color.white.opacity(0.06)
        /// Text fields & secondary pills (Send reference).
        static let fieldFill = Color(hex: 0x1A1A1E)
        static let fieldFillPressed = Color(hex: 0x222226)
        static let listCardFill = Color(hex: 0x1A1A1A)
        static let tabBarFill = Color(hex: 0x1C1C1E)
        static let tabBarActiveFill = Color(hex: 0x2C2C2E)
        static let shieldGreen = Color(hex: 0xB8F94A)
        static let privacyBadgeFill = Color(hex: 0x248A3D)
        static let errorBadge = Color(hex: 0x5C2D2D)

        static let success = Color(hex: 0x34C759)
        static let warning = Color(hex: 0xFF9F0A)

        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.55)
        static let textTertiary = Color.white.opacity(0.35)

        /// Wallet home — белый текст и кнопки приглушены.
        static let homeTextPrimary = Color.white.opacity(0.82)
        static let homeCircleButtonFill = Color.white.opacity(0.08)
        static let homeCircleButtonStroke = Color.white.opacity(0.14)
        static let homeChromeIcon = Color.white.opacity(0.80)
        static let homeTextSecondary = Color.white.opacity(0.48)

        static let buttonPrimaryFill = accent
        static let buttonPrimaryText = Color.white
        static let buttonSecondaryFill = Color.clear
        static let buttonSecondaryText = Color.white

        static let border = Color.white.opacity(0.12)
        static let borderSubtle = Color.white.opacity(0.08)
        static let divider = Color.white.opacity(0.08)

        // Legacy aliases
        static let glassFill = Color.clear
        static let glassFillStrong = Color.clear
        static let glassStroke = border
        static let glassStrokeSubtle = borderSubtle
        static let glassStrokeFaint = borderSubtle
        static let glassHighlight = Color.clear
        static let gradientTop = background
        static let gradientMid = background
        static let gradientBottom = background
        static let accentPrimary = accent

        static let brandGradient = LinearGradient(
            colors: [
                Color.white,
                Color(hex: 0xC9B5E4),
                Color(hex: 0xA18DCA)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    enum Metrics {
        static let screenPadding: CGFloat = 24
        static let cardRadius: CGFloat = 16
        static let buttonRadius: CGFloat = 28
        static let buttonHeight: CGFloat = 56
        static let chromeButtonSize: CGFloat = 48
        /// Tap target for close/back chrome (matches visual disc).
        static let chromeHitTargetSize: CGFloat = 48
        static let circleButtonSize: CGFloat = 56
        static let welcomeCircleButtonSize: CGFloat = 72
        static let fieldRadius: CGFloat = 14
        static let iconBoxSize: CGFloat = 40
        static let sectionSpacing: CGFloat = 24
        static let cardPadding: CGFloat = 16
        static let monogramSize: CGFloat = 32
        static let walletCardRadius: CGFloat = 24
        static let passcodeDotSize: CGFloat = 11
        /// Wallet home hero — expanded balance (auto-shrinks when the amount is long).
        static let walletHomeBalanceExpandedSize: CGFloat = 52
        static let walletHomeBalanceCollapsedSize: CGFloat = 22
    }

    enum Typography {
        /// Geist Sans — bundled in `Fonts/Geist`.
        static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            MeshFont.font(size: size, weight: weight)
        }

        static func hero() -> Font { sans(size: 36, weight: .light) }
        static func balanceHero() -> Font { sans(size: 48, weight: .semibold) }
        static func balanceCurrency() -> Font { sans(size: 22, weight: .light) }
        static func screenTitle() -> Font { sans(size: 32, weight: .semibold) }
        static func sectionTitle() -> Font { sans(size: 19, weight: .regular) }
        static func button() -> Font { sans(size: 18, weight: .medium) }
        static func buttonPrimary() -> Font { sans(size: 18, weight: .medium) }
        static func brandTitle() -> Font { sans(size: 34, weight: .light) }
        static func body() -> Font { sans(size: 17, weight: .regular) }
        static func secondary() -> Font { sans(size: 16, weight: .light) }
        static func caption() -> Font { sans(size: 14, weight: .light) }
        static func label() -> Font { sans(size: 13, weight: .light) }
        /// SF Symbols keep system sizing; text uses Geist via `sans`.
        static func icon(size: CGFloat, weight: Font.Weight = .light) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
    }
}

private struct MeshScreenFooterButtonsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true, `MeshPrimaryButton` / `MeshSecondaryButton` are laid out as 56pt footer CTAs.
    var meshScreenFooterButtons: Bool {
        get { self[MeshScreenFooterButtonsKey.self] }
        set { self[MeshScreenFooterButtonsKey.self] = newValue }
    }
}

extension View {
    /// Bottom-of-screen capsule actions: full width, 56pt tall, solid fill (no Liquid Glass).
    func meshScreenFooterButtons() -> some View {
        environment(\.meshScreenFooterButtons, true)
    }

    /// Outlined panel on black.
    func meshSurfacePanel(cornerRadius: CGFloat = MeshTheme.Metrics.cardRadius) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(MeshTheme.Colors.border, lineWidth: 1)
        )
    }

    /// Filled field — Send reference input style.
    func meshFieldSurface(cornerRadius: CGFloat = MeshTheme.Metrics.fieldRadius) -> some View {
        background(
            MeshTheme.Colors.fieldFill,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    /// Purple caret and selection tint for text fields and editors.
    func meshTextInputAccent() -> some View {
        tint(MeshTheme.Colors.accent)
    }

    func meshGlassPanel(cornerRadius: CGFloat = MeshTheme.Metrics.cardRadius) -> some View {
        meshSurfacePanel(cornerRadius: cornerRadius)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >> 8) & 0xff) / 255
        let b = Double(hex & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
