import SwiftUI

struct SendReviewStepView: View {
    @ObservedObject var model: SendFlowViewModel
    let onBack: () -> Void
    let onBeginSend: () -> Void

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard
                        networkCard

                        if let error = model.sendReviewVisibleError {
                            Text(error)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(Color.orange)
                                .padding(.top, 4)
                        } else if let hint = model.spendSourceHint {
                            Text(hint)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(MeshTheme.Colors.textTertiary)
                                .padding(.top, 4)
                        }
                        Text(L10n.Send.reviewWarning)
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 8) {
                    if let hint = model.sendReviewPrepHint {
                        Text(hint)
                            .font(MeshTheme.Typography.sans(size: 12, weight: .regular))
                            .foregroundStyle(MeshTheme.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    MeshSlideToSend(
                        title: model.sendReviewSliderTitle,
                        isEnabled: model.canSlideToSend,
                        showsPreparingActivity: model.isSendReviewPreparing,
                        usesCompactTitle: model.isSendReviewPreparing
                    ) {
                        onBeginSend()
                    }
                    .animation(.easeInOut(duration: 0.2), value: model.sendReviewSliderTitle)
                }
                .animation(.easeInOut(duration: 0.2), value: model.sendReviewPrepHint)
                .meshScreenFooterButtons()
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .meshOnboardingChrome(onBack: onBack)
        .task {
            TronBlockService.prefetchLatestBlock()
            if model.hasAuthoritativeSpendableBalance {
                await model.refreshReviewValidation()
            } else {
                await model.loadWalletState()
                model.revalidateDraftAfterBalanceRefresh()
                await model.refreshReviewValidation()
            }
        }
    }

    private var header: some View {
        MeshFlowScreenHeader(
            title: L10n.Send.reviewTitle,
            onClose: onBack,
            trailingText: L10n.Send.stepProgress,
            usesBackButton: true
        )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Send.reviewSending)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                Text(model.reviewAmountText)
                    .font(MeshTheme.Typography.sans(size: 28, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Send.reviewTo)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                Text(TronUSDTService.shortAddress(model.recipientAddress))
                    .font(MeshTheme.Typography.sectionTitle())
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeshTheme.Colors.listCardFill, in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous))
    }

    private var networkCard: some View {
        VStack(spacing: 0) {
            reviewRow(label: L10n.Send.reviewNetwork, value: "TRC-20")
            if MeshSendFees.showsFeeInUI {
                divider
                reviewRow(label: L10n.Send.feeLabel, value: model.networkFeeText)
            }
            divider
            reviewRow(label: L10n.Send.reviewTotal, value: model.reviewTotalText)
            divider
            reviewRow(label: L10n.Send.reviewArrives, value: L10n.Send.timingDirect)
        }
        .padding(.vertical, 4)
        .background(MeshTheme.Colors.listCardFill, in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(MeshTheme.Colors.divider)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func reviewRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MeshTheme.Typography.secondary())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(MeshTheme.Typography.body())
                .foregroundStyle(MeshTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

}
