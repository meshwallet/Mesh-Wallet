import SwiftUI

extension View {
    /// Soft settle after balance refresh: slight lift + fade, no scale pop or accent flash.
    func walletHomeBalanceRefreshSettle(phase: CGFloat) -> some View {
        let wave = sin(Double(min(max(phase, 0), 1)) * .pi)
        return offset(y: CGFloat(-4 * wave))
            .opacity(1 - wave * 0.11)
    }

    func walletHomeBalanceAmountStyle(hidden: Bool) -> some View {
        foregroundStyle(hidden ? MeshTheme.Colors.textTertiary : MeshTheme.Colors.homeTextPrimary)
    }

    func walletHomeBalanceSecondaryStyle() -> some View {
        foregroundStyle(MeshTheme.Colors.homeTextSecondary)
    }

    /// Hide balance in place — blur + fade, same feel as the USDT label on the home hero.
    func walletHomeBalancePrivacyBlur(
        isHidden: Bool,
        visibleOpacity: Double = 1,
        hiddenOpacity: Double = 0.4,
        blurRadius: CGFloat = 6
    ) -> some View {
        opacity(isHidden ? hiddenOpacity : visibleOpacity)
            .blur(radius: isHidden ? blurRadius : 0)
    }
}

/// Balance amount with numeric crossfade when the value changes.
/// Fractional digits (after `.`) use the same secondary style as the USDT label.
struct WalletHomeAnimatedBalanceText: View {
    let text: String
    let fontSize: CGFloat
    let fractionalFontSize: CGFloat
    let hidden: Bool
    let staleOpacity: Double
    let settlePhase: CGFloat

    private var parts: (whole: String, fractional: String) {
        guard let dot = text.lastIndex(of: ".") else {
            return (text, "")
        }
        return (String(text[..<dot]), String(text[dot...]))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(parts.whole)
                .font(MeshTheme.Typography.sans(size: fontSize, weight: .semibold))
                .walletHomeBalanceAmountStyle(hidden: hidden)
                .walletHomeBalanceRefreshSettle(phase: settlePhase)
                .opacity(staleOpacity)
                .modifier(MeshNumericTextTransition())

            if !parts.fractional.isEmpty {
                Text(parts.fractional)
                    .font(MeshTheme.Typography.sans(size: fractionalFontSize, weight: .light))
                    .walletHomeBalanceSecondaryStyle()
                    .walletHomeBalanceRefreshSettle(phase: settlePhase)
                    .opacity(staleOpacity)
                    .modifier(MeshNumericTextTransition())
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.38)
        .allowsTightening(true)
        .monospacedDigit()
        .animation(MeshBalanceRevealAnimation.valueChange, value: text)
    }
}
