import SwiftUI

struct WalletPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meshModalClose) private var meshModalClose
    @Environment(\.meshInteractiveDismiss) private var meshInteractiveDismiss
    @State private var defaultSendMethod = MeshPrivacyStore.defaultSendMethod()
    @State private var isConsolidating = false
    @State private var consolidateProgressCurrent = 0
    @State private var consolidateProgressTotal = 0
    @State private var consolidateStatus: String?
    @State private var consolidateError: String?

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                MeshFlowScreenHeader(title: L10n.Privacy.title, onClose: closeModal)
                    .padding(.top, 4)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        receivePrivacyCard
                        sendMethodsCard
                        protectionCard
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            defaultSendMethod = MeshPrivacyStore.defaultSendMethod()
        }
    }

    private func closeModal() {
        MeshModalClose.perform(
            modalClose: meshModalClose,
            interactiveDismiss: meshInteractiveDismiss,
            dismiss: dismiss
        )
    }

    private var receivePrivacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Privacy.receiveTitle)
                .font(MeshTheme.Typography.sectionTitle())
                .foregroundStyle(MeshTheme.Colors.textPrimary)

            Text(L10n.Privacy.receiveBody)
            .font(MeshTheme.Typography.secondary())
            .foregroundStyle(MeshTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeshTheme.Colors.listCardFill, in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous))
    }

    private var sendMethodsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Privacy.sendTitle)
                .font(MeshTheme.Typography.sectionTitle())
                .foregroundStyle(MeshTheme.Colors.textPrimary)

            Text(L10n.Privacy.sendBody)
                .font(MeshTheme.Typography.secondary())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(MeshDefaultSendMethod.allCases) { method in
                    sendMethodRow(method)
                }
            }

            if MeshWalletCredentials.supportsHDWalletFeatures() {
                slotConsolidationSection
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeshTheme.Colors.listCardFill, in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous))
    }

    private func sendMethodRow(_ method: MeshDefaultSendMethod) -> some View {
        let isSelected = defaultSendMethod == method

        return Button {
            defaultSendMethod = method
            MeshPrivacyStore.setDefaultSendMethod(method)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(method.title)
                        .font(MeshTheme.Typography.sans(size: 15, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    if isSelected {
                        Text(L10n.Common.defaultLabel)
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MeshTheme.Colors.accent.opacity(0.35), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MeshTheme.Colors.accent)
                    }
                }

                Text(method.detail)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    if MeshSendFees.showsFeeInUI {
                        Text(L10n.Common.feeFormat(MeshSendFees.formattedFee(method.fee)))
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textTertiary)
                    }

                    Text(method.timing)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textTertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MeshTheme.Colors.surfaceElevated.opacity(0.35),
                in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
                    .stroke(isSelected ? MeshTheme.Colors.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var slotConsolidationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(MeshTheme.Colors.borderSubtle)
                .padding(.top, 4)

            Text(L10n.Privacy.consolidateTitle)
                .font(MeshTheme.Typography.sans(size: 15, weight: .semibold))
                .foregroundStyle(MeshTheme.Colors.textPrimary)

            Text(L10n.Privacy.consolidateHint)
                .font(MeshTheme.Typography.secondary())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let status = consolidateStatus {
                Text(status)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.success)
            }

            if let error = consolidateError {
                Text(error)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(Color.orange)
            }

            if isConsolidating, consolidateProgressTotal > 0 {
                Text(
                    L10n.Privacy.consolidateProgress(
                        current: consolidateProgressCurrent,
                        total: consolidateProgressTotal
                    )
                )
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
                .monospacedDigit()
            }

            MeshSecondaryButton(
                title: isConsolidating
                    ? L10n.Privacy.consolidateRunning
                    : L10n.Privacy.consolidateButton,
                isEnabled: !isConsolidating
            ) {
                startSlotConsolidation()
            }
            .meshScreenFooterButtons()
        }
        .padding(.top, 4)
    }

    private func startSlotConsolidation() {
        guard !isConsolidating else { return }
        isConsolidating = true
        consolidateError = nil
        consolidateStatus = nil
        consolidateProgressCurrent = 0
        consolidateProgressTotal = 0

        Task {
            do {
                let count = try await MeshPrivacyService.consolidateFiveReceiveSlotsToMainWallet { current, total in
                    consolidateProgressCurrent = current
                    consolidateProgressTotal = total
                }
                consolidateStatus = L10n.Privacy.consolidateDone(count)
            } catch {
                consolidateError = SendErrorPresenter.message(for: error)
            }
            isConsolidating = false
        }
    }

    private var protectionItems: [String] {
        [
            L10n.Privacy.protectionItem1,
            L10n.Privacy.protectionItem2,
            L10n.Privacy.protectionItem3
        ]
    }

    private var protectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Privacy.protectionTitle)
                .font(MeshTheme.Typography.sectionTitle())
                .foregroundStyle(MeshTheme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(protectionItems, id: \.self) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(MeshTheme.Typography.sans(size: 11, weight: .semibold))
                            .foregroundStyle(MeshTheme.Colors.textPrimary)
                            .frame(width: 22, height: 22)
                            .background(MeshTheme.Colors.success, in: Circle())

                        Text(item)
                            .font(MeshTheme.Typography.body())
                            .foregroundStyle(MeshTheme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeshTheme.Colors.listCardFill, in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous))
    }

}
