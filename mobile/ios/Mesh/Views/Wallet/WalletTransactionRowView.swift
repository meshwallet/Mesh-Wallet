import SwiftUI

struct WalletTransactionRowView: View {
    enum Style {
        case compact
        case rich
        case home
    }

    let transaction: WalletTransaction
    var balanceHidden: Bool = false
    var style: Style = .compact
    var showsDivider: Bool = true
    var showsDate: Bool = true

    private var accent: Color {
        switch transaction.transferStatus {
        case .processing:
            return MeshTheme.Colors.accent
        case .failed:
            return Color.orange
        case .confirmed:
            return MeshTransactionVisuals.accentColor(incoming: transaction.isIncoming)
        }
    }

    var body: some View {
        HStack(spacing: style == .rich ? 16 : 14) {
            iconView

            VStack(alignment: .leading, spacing: style == .rich ? 5 : 4) {
                Text(transaction.listTitle)
                    .font(MeshTheme.Typography.sans(size: titleFontSize, weight: .medium))
                    .foregroundStyle(style == .home ? MeshTheme.Colors.homeTextPrimary : MeshTheme.Colors.textPrimary)
                Text(subtitleText)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(transaction.amountText)
                    .font(MeshTheme.Typography.sans(size: style == .rich ? 16 : 15, weight: .semibold))
                    .foregroundStyle(visibleAmountColor)
                    .walletHomeBalancePrivacyBlur(isHidden: balanceHidden, blurRadius: 6)
                    .animation(.easeInOut(duration: 0.28), value: balanceHidden)
                if showsTrailingTime {
                    Text(transaction.listRowTimeText)
                        .font(MeshTheme.Typography.label())
                        .foregroundStyle(
                            style == .home
                                ? MeshTheme.Colors.homeTextSecondary.opacity(0.72)
                                : MeshTheme.Colors.textTertiary
                        )
                }
            }

            if style == .rich {
                Image(systemName: "chevron.right")
                    .font(MeshTheme.Typography.icon(size: 11, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textTertiary.opacity(0.7))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .overlay(alignment: .bottom) {
            if showsDivider {
                MeshHairlineDivider(leadingInset: dividerLeadingInset)
            }
        }
        .contentShape(Rectangle())
    }

    private var titleFontSize: CGFloat {
        switch style {
        case .rich: return 17
        case .home: return 17
        case .compact: return 16
        }
    }

    private var subtitleText: String {
        switch style {
        case .rich:
            return transaction.listSubtitle
        case .home:
            return TronUSDTService.shortAddress(transaction.counterpartyAddress)
        case .compact:
            return transaction.subtitle
        }
    }

    private var showsTrailingTime: Bool {
        showsDate || style == .home || style == .rich
    }

    private var horizontalPadding: CGFloat {
        style == .rich || style == .home ? 0 : 16
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .rich: return 18
        case .home: return 16
        case .compact: return 14
        }
    }

    private var dividerLeadingInset: CGFloat {
        switch style {
        case .rich: return 56
        case .home: return 56
        case .compact: return 70
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if style == .home {
            ZStack {
                Circle()
                    .fill(MeshTheme.Colors.surfaceElevated)
                    .frame(width: 44, height: 44)
                Image(systemName: homeIconName)
                    .font(MeshTheme.Typography.icon(size: 16, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.homeTextPrimary)
            }
        } else if style == .rich {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.45), lineWidth: 1)
                    .frame(width: 40, height: 40)
                Image(systemName: rowIconName)
                    .font(MeshTheme.Typography.icon(size: 14, weight: .light))
                    .foregroundStyle(accent)
            }
        } else {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 40, height: 40)
                Image(systemName: compactIconName)
                    .font(MeshTheme.Typography.icon(size: 14, weight: .semibold))
                    .foregroundStyle(iconForeground)
            }
        }
    }

    private var rowIconName: String {
        if transaction.isProcessing {
            return "clock"
        }
        return transaction.kind == .sent ? "arrow.up.right" : "arrow.down.left"
    }

    private var homeIconName: String {
        if transaction.isProcessing {
            return "clock"
        }
        return transaction.kind == .sent ? "arrow.up" : "arrow.down"
    }

    private var compactIconName: String {
        if transaction.isProcessing {
            return "clock"
        }
        return transaction.kind == .sent ? "arrow.up" : "arrow.down"
    }

    private var iconBackground: Color {
        transaction.isIncoming
            ? MeshTheme.Colors.success.opacity(0.18)
            : MeshTheme.Colors.surfaceElevated
    }

    private var iconForeground: Color {
        transaction.isIncoming ? MeshTheme.Colors.success : MeshTheme.Colors.textPrimary
    }

    private var visibleAmountColor: Color {
        if style == .home {
            return transaction.isIncoming ? MeshTheme.Colors.success : MeshTheme.Colors.homeTextPrimary
        }
        return transaction.isIncoming ? MeshTheme.Colors.success : MeshTheme.Colors.textPrimary
    }
}
