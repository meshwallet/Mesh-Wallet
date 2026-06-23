import SwiftUI

/// Thin scrolling ticker for the wallet home screen.
struct MeshHomeTicker: View {
    let messages: [String]

    private var marqueeText: String {
        let items = messages.filter { !$0.isEmpty }
        guard !items.isEmpty else { return "Mesh Wallet · USDT on Tron" }
        let core = items.joined(separator: " - ")
        return core + " - "
    }

    var body: some View {
        MeshMarqueeLabel(text: marqueeText)
            .frame(height: 26)
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            .padding(.bottom, 6)
    }
}

private struct MeshMarqueeLabel: View {
    let text: String

    private let segmentSpacing: CGFloat = 0

    @State private var segmentWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    var body: some View {
        GeometryReader { _ in
            HStack(spacing: segmentSpacing) {
                segmentLabel
                    .background(
                        GeometryReader { textProxy in
                            Color.clear.preference(
                                key: MarqueeWidthKey.self,
                                value: textProxy.size.width
                            )
                        }
                    )
                segmentLabel
            }
            .offset(x: offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .onPreferenceChange(MarqueeWidthKey.self) { width in
                guard width > 0, abs(width - segmentWidth) > 0.5 else { return }
                segmentWidth = width
                restartLoop()
            }
        }
        .frame(height: 26)
        .clipped()
        .mask(edgeFadeMask)
        .id(text)
    }

    private var segmentLabel: some View {
        Text(text)
            .font(MeshTheme.Typography.sans(size: 11, weight: .medium))
            .foregroundStyle(MeshTheme.Colors.textTertiary)
            .tracking(0.2)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var loopDistance: CGFloat {
        segmentWidth + segmentSpacing
    }

    private func restartLoop() {
        guard loopDistance > 0 else { return }

        offset = 0

        let duration = max(10, Double(loopDistance) / 24)

        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -loopDistance
        }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum MeshHomeTickerMessages {
    static func items(
        hasPendingSend: Bool,
        isPrivateSendEnabled: Bool
    ) -> [String] {
        var lines: [String] = []

        if hasPendingSend {
            lines.append("  Send in progress · check Recent for live status  ")
        }

        if MeshSendFees.showsFeeInUI {
            lines.append(
                "  Direct send \(MeshSendFees.formattedFee(MeshSendFees.directSend)) · Private from \(MeshSendFees.formattedFee(MeshSendFees.standardPrivate))  "
            )
            lines.append("  \(L10n.Ticker.networkFees)  ")
        }
        lines.append("  Pull down to refresh balance and activity  ")

        if isPrivateSendEnabled {
            lines.append("  Private send hides your main address using relay wallets  ")
        } else {
            lines.append("  Enable Private send for relay transfers from Settings  ")
        }

        lines.append("  TRC-20 USDT on Tron · confirmations usually under 2 minutes  ")
        lines.append("  Transfers keep running if you close the send screen  ")
        lines.append("  Privacy · Keep your real balance private  ")

        return lines
    }
}
