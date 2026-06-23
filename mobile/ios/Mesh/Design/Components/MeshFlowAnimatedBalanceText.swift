import SwiftUI

enum MeshBalanceRevealAnimation {
    static let reveal = Animation.spring(response: 0.55, dampingFraction: 0.86)
    static let valueChange = Animation.spring(response: 0.52, dampingFraction: 0.88)
    static let listExpand = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static func staggeredReveal(index: Int) -> Animation {
        .spring(response: 0.55, dampingFraction: 0.86)
            .delay(Double(index) * 0.045)
    }
}

struct MeshNumericTextTransition: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentTransition(.numericText(countsDown: false))
        } else {
            content.transition(.opacity)
        }
    }
}

/// Balance label for send/receive slot rows — soft fade from placeholder to loaded value.
struct MeshFlowAnimatedBalanceText: View {
    let text: String
    let font: Font
    var color: Color = MeshTheme.Colors.textSecondary
    var isPending: Bool

    var body: some View {
        Text(isPending ? "—" : text)
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .opacity(isPending ? 0.42 : 1)
            .blur(radius: isPending ? 2 : 0)
            .scaleEffect(isPending ? 0.97 : 1, anchor: .trailing)
            .modifier(MeshNumericTextTransition())
            .animation(MeshBalanceRevealAnimation.reveal, value: isPending)
            .animation(MeshBalanceRevealAnimation.valueChange, value: text)
    }
}

/// Caption line under send amount (e.g. "Available on this address: 12.34 USDT").
struct MeshFlowAnimatedAvailableCaption: View {
    let fullText: String
    let isPending: Bool

    var body: some View {
        Text(fullText)
            .font(MeshTheme.Typography.caption())
            .foregroundStyle(MeshTheme.Colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .opacity(isPending ? 0.5 : 1)
            .blur(radius: isPending ? 1.5 : 0)
            .modifier(MeshNumericTextTransition())
            .animation(MeshBalanceRevealAnimation.reveal, value: isPending)
            .animation(MeshBalanceRevealAnimation.valueChange, value: fullText)
    }
}
