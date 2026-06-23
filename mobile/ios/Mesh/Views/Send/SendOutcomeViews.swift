import SwiftUI

struct SendSuccessView: View {
    @ObservedObject var model: SendFlowViewModel
    let txID: String
    let onDone: () -> Void

    var body: some View {
        MeshTransferProofExperience(
            transaction: model.sentTransaction(txID: txID, transferStatus: .confirmed),
            onClose: onDone,
            usesSheetChrome: false
        )
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SendFailedView: View {
    @ObservedObject var model: SendFlowViewModel
    let message: String
    let onCancel: () -> Void

    @State private var showDetails = false
    @State private var inAppBrowserURL: URL?

    private var displayMessage: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Network rejected the transaction. Your balance hasn't changed."
        }
        return SendErrorPresenter.message(
            for: TronAPIError.broadcastFailed(trimmed)
        )
    }

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 32)

                ZStack {
                    Circle()
                        .fill(MeshTheme.Colors.errorBadge.opacity(0.2))
                        .frame(width: 120, height: 120)
                    Circle()
                        .stroke(MeshTheme.Colors.errorBadge.opacity(0.4), lineWidth: 2)
                        .frame(width: 120, height: 120)
                    Image(systemName: "xmark")
                        .font(MeshTheme.Typography.sans(size: 40, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                        .frame(width: 88, height: 88)
                        .background(MeshTheme.Colors.errorBadge, in: Circle())
                }

                VStack(spacing: 10) {
                    Text(L10n.Send.failed)
                        .font(MeshTheme.Typography.screenTitle())
                        .foregroundStyle(MeshTheme.Colors.textPrimary)

                    Text(displayMessage)
                        .font(MeshTheme.Typography.secondary())
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Text(feeHint)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 4)
                }
                .padding(.top, 28)

                sendSummaryCard
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 28)

                Spacer()

                VStack(spacing: 12) {
                    MeshPrimaryButton(title: L10n.Send.transactionDetails) {
                        showDetails = true
                    }
                    MeshSecondaryButton(title: L10n.Common.contact) {
                        inAppBrowserURL = MeshAppLinks.contactPage
                    }
                    MeshSecondaryButton(title: L10n.Common.close, action: onCancel)
                }
                .meshScreenFooterButtons()
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.bottom, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDetails) {
            WalletTransactionDetailView(transaction: model.makePendingTransaction()) {
                showDetails = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground {
                MeshSelectWalletSheetBackground()
            }
        }
        .meshInAppBrowserSheet(url: $inAppBrowserURL)
    }

    private var feeHint: String {
        MeshSendFees.enforcesOnChainSendFees
            ? L10n.Send.failedFeeHint
            : "No USDT left your wallet."
    }

    private var sendSummaryCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.Send.amount)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                Spacer()
                Text(model.reviewAmountText)
                    .font(MeshTheme.Typography.sans(size: 16, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle()
                .fill(MeshTheme.Colors.divider)
                .frame(height: 1)
                .padding(.leading, 16)

            HStack {
                Text(L10n.Send.reviewTo)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                Spacer()
                Text(TronUSDTService.shortAddress(model.recipientAddress))
                    .font(MeshTheme.Typography.body())
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(
            MeshTheme.Colors.listCardFill,
            in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
        )
    }
}
