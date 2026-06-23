import SwiftUI

struct WalletTransactionDetailView: View {
    let transaction: WalletTransaction
    let onClose: () -> Void

    var body: some View {
        if transaction.isProofEligible {
            MeshTransferProofExperience(transaction: transaction, onClose: onClose)
        } else {
            WalletTransactionTechnicalDetailView(transaction: transaction, onClose: onClose)
        }
    }
}

private struct WalletTransactionTechnicalDetailView: View {
    let transaction: WalletTransaction
    let onClose: () -> Void

    @State private var didCopyTxID = false
    @State private var didCopyFrom = false
    @State private var didCopyTo = false
    @State private var inAppBrowserURL: URL?

    private var accent: Color {
        switch transaction.transferStatus {
        case .processing:
            return MeshTheme.Colors.accent
        case .confirmed:
            return MeshTransactionVisuals.accentColor(incoming: transaction.isIncoming)
        case .failed:
            return Color.orange
        }
    }

    private var statusCaptionColor: Color {
        switch transaction.transferStatus {
        case .processing:
            return MeshTheme.Colors.accent
        case .confirmed:
            return MeshTheme.Colors.textTertiary
        case .failed:
            return Color.orange
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MeshSelectWalletSheetBackground()

            VStack(spacing: 0) {
                sheetHeader

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                        MeshHairlineDivider()
                            .padding(.vertical, 8)
                        detailsSection
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.bottom, 24)
                }

                footerActions
                    .meshScreenFooterButtons()
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(
            get: { inAppBrowserURL != nil },
            set: { if !$0 { inAppBrowserURL = nil } }
        )) {
            if let url = inAppBrowserURL {
                MeshInAppBrowserSheet(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    private var sheetHeader: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(MeshTheme.Colors.textTertiary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 20)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.TransferProof.detailsTitle)
                        .font(MeshTheme.Typography.sans(size: 22, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    Text("TRC-20 · \(statusCaptionText)")
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(statusCaptionColor)
                }
                Spacer()
                Button(L10n.Common.done, action: onClose)
                    .buttonStyle(.plain)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
            }
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            .padding(.bottom, 8)
        }
    }

    private var heroSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.4), lineWidth: 1)
                    .frame(width: 76, height: 76)
                heroIcon
            }
            .padding(.top, 28)

            VStack(spacing: 12) {
                Text(transaction.amountDetailText)
                    .font(MeshTheme.Typography.sans(size: 40, weight: .semibold))
                    .foregroundStyle(transaction.isIncoming ? MeshTheme.Colors.success : MeshTheme.Colors.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                HStack(spacing: 16) {
                    metaLabel(transaction.title, accent: accent)
                    metaLabel("USDT", accent: MeshTheme.Colors.textSecondary)
                    metaLabel("Tron", accent: MeshTheme.Colors.textTertiary)
                }

                Text(transaction.formattedDateTime)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var heroIcon: some View {
        switch transaction.transferStatus {
        case .processing:
            Image(systemName: "clock")
                .font(MeshTheme.Typography.icon(size: 26, weight: .light))
                .foregroundStyle(accent)
        case .confirmed, .failed:
            Image(systemName: transaction.kind == .sent ? "arrow.up.right" : "arrow.down.left")
                .font(MeshTheme.Typography.icon(size: 24, weight: .light))
                .foregroundStyle(accent)
        }
    }

    private func metaLabel(_ text: String, accent: Color) -> some View {
        Text(text)
            .font(MeshTheme.Typography.sans(size: 12, weight: .medium))
            .tracking(0.3)
            .foregroundStyle(accent)
    }

    private var detailsSection: some View {
        VStack(spacing: 0) {
            MeshTransactionDetailField(
                icon: "clock",
                title: L10n.TransferProof.status,
                value: statusDisplayText,
                expandable: isFailedTransaction
            )
            MeshHairlineDivider()
            MeshTransactionDetailField(
                icon: "text.alignleft",
                title: L10n.TransferProof.detailsField,
                value: failureDetailsBody,
                expandable: isFailedTransaction
            )
            MeshHairlineDivider()
            MeshTransactionDetailField(
                icon: "arrow.up.forward",
                title: L10n.TransferProof.from,
                value: transaction.fromAddress,
                truncateMiddle: true,
                onCopy: { copy(transaction.fromAddress, key: "from") },
                copied: didCopyFrom
            )
            MeshHairlineDivider()
            MeshTransactionDetailField(
                icon: "arrow.down.forward",
                title: L10n.TransferProof.to,
                value: transaction.toAddress,
                truncateMiddle: true,
                onCopy: { copy(transaction.toAddress, key: "to") },
                copied: didCopyTo
            )
            MeshHairlineDivider()
            MeshTransactionDetailField(
                icon: "link",
                title: L10n.TransferProof.tx,
                value: transaction.displayTxID,
                isMonospace: true,
                truncateMiddle: true,
                onCopy: transaction.txID.isEmpty ? nil : { copy(transaction.txID, key: "tx") },
                copied: didCopyTxID
            )
        }
    }

    private var isFailedTransaction: Bool {
        if case .failed = transaction.transferStatus { return true }
        return false
    }

    private var statusCaptionText: String {
        if let detail = transaction.failureDetailText {
            return detail
        }
        return transaction.transferStatus.title
    }

    private var statusDisplayText: String {
        if let detail = transaction.failureDetailText {
            return detail
        }
        return transaction.transferStatus.title
    }

    private var failureDetailsBody: String {
        switch transaction.transferStatus {
        case .failed:
            if transaction.txID.isEmpty {
                return "No transaction was broadcast to the Tron network."
            }
            return "Transaction ID: \(transaction.displayTxID)"
        default:
            return transaction.transferStatus.detailSubtitle
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        if case .confirmed = transaction.transferStatus, transaction.tronscanURL != nil {
            MeshPrimaryButton(title: L10n.TransferProof.viewOnTronscan, icon: "arrow.up.right") {
                openTronscan()
            }
        }
    }

    private func copy(_ value: String, key: String) {
        guard MeshClipboard.copy(value) else { return }
        switch key {
        case "tx":
            didCopyTxID = true
            resetCopy { didCopyTxID = false }
        case "from":
            didCopyFrom = true
            resetCopy { didCopyFrom = false }
        case "to":
            didCopyTo = true
            resetCopy { didCopyTo = false }
        default:
            break
        }
    }

    private func resetCopy(_ reset: @escaping () -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { reset() }
        }
    }

    private func openTronscan() {
        guard let url = transaction.tronscanURL else { return }
        inAppBrowserURL = url
    }
}
