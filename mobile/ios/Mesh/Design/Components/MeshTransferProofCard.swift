import SwiftUI

struct MeshTransferProofCard: View {
    let transaction: WalletTransaction
    var style: Style = .standard

    enum Style {
        case standard
        case shareImage
    }

    private var showsCleanHeadline: Bool {
        style == .shareImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsCleanHeadline {
                Text(transaction.proofCleanHeadline)
                    .font(MeshTheme.Typography.sans(size: 17, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .padding(.bottom, 20)
            } else {
                Text(transaction.proofAmountText)
                    .font(MeshTheme.Typography.sans(size: 40, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 24)
            }

            proofRow(label: L10n.TransferProof.status, value: transaction.proofStatusText)
            MeshHairlineDivider()
                .padding(.vertical, 12)
            proofRow(label: L10n.TransferProof.networkLabel, value: transaction.proofNetworkText)
            MeshHairlineDivider()
                .padding(.vertical, 12)
            proofRow(label: transaction.proofCounterpartyTitle, value: transaction.proofShortCounterparty)

            if !transaction.txID.isEmpty {
                MeshHairlineDivider()
                    .padding(.vertical, 12)
                proofRow(label: L10n.TransferProof.tx, value: transaction.proofShortTxID, isMonospace: true)
            }

            MeshHairlineDivider()
                .padding(.vertical, 12)
            proofRow(label: L10n.TransferProof.date, value: transaction.formattedDateTime)

            proofBranding
                .padding(.top, 28)
        }
        .padding(24)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .stroke(MeshTheme.Colors.borderSubtle, lineWidth: 1)
        }
    }

    private var cardFillColor: Color {
        MeshTheme.Colors.listCardFill.opacity(0.55)
    }

    private var proofBranding: some View {
        VStack(spacing: 6) {
            Image("IconPng")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .accessibilityLabel(L10n.Welcome.brand)
            Text(L10n.TransferProof.tagline)
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var cardRadius: CGFloat {
        style == .shareImage ? MeshTheme.Metrics.walletCardRadius : MeshTheme.Metrics.cardRadius
    }

    private func proofRow(label: String, value: String, isMonospace: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(MeshTheme.Typography.sans(size: 13, weight: .medium))
                .foregroundStyle(MeshTheme.Colors.textTertiary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(
                    isMonospace
                        ? MeshTheme.Typography.sans(size: 15, weight: .regular)
                        : MeshTheme.Typography.sans(size: 15, weight: .medium)
                )
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

#if canImport(UIKit)
import UIKit

enum MeshTransferProofImageRenderer {
    @MainActor
    static func image(for transaction: WalletTransaction) -> UIImage? {
        let content = ZStack {
            MeshTheme.Colors.background
            MeshTransferProofCard(transaction: transaction, style: .shareImage)
                .padding(28)
        }
        .frame(width: 390, height: 560)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
#endif
