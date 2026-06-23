import SwiftUI

/// Submitted screen: handoff runs in `MeshBackgroundSendService`; user can leave once handoff is on Mesh.
struct SendSubmittedView: View {
    @ObservedObject private var sendService = MeshBackgroundSendService.shared
    let model: SendFlowViewModel
    let onClose: () -> Void

    @State private var onChainVerified = false
    @State private var inAppBrowserURL: URL?

    private var pending: MeshBackgroundSendService.PendingTransfer? {
        if let sendID = model.activePendingSendID,
           let pinned = sendService.pendingTransfer(id: sendID)
        {
            return pinned
        }
        if let current = sendService.current {
            return current
        }
        return sendService.trackedTransfers.first(where: \.transaction.isProcessing)
    }

    private var transferStatus: WalletTransaction.TransferStatus {
        pending?.transaction.transferStatus ?? .processing
    }

    private var hasSubmittedTxID: Bool {
        guard let txID = pending?.transaction.txID else { return false }
        return TronUSDTService.isPlausibleTronTransactionID(txID)
    }

    private var isPreparingHandoff: Bool {
        guard !isFailed, !showsHandoffSuccess else { return false }
        return pending?.handoffRegistered != true
    }

    private var canLeaveInBackground: Bool {
        guard !isFailed else { return false }
        return pending?.handoffRegistered == true
    }

    /// Green check once signed txs are registered with Cloudflare.
    private var showsHandoffSuccess: Bool {
        guard !isFailed else { return false }
        return pending?.handoffRegistered == true
    }

    /// Full on-chain confirmation — upgrades subtitle once Tron indexes the transfer.
    private var showsOnChainSuccess: Bool {
        onChainVerified
    }

    private var isFailed: Bool {
        if case .failed = transferStatus { return true }
        return false
    }

    private var isSent: Bool {
        if case .confirmed = transferStatus { return true }
        return false
    }

    private var displayTransaction: WalletTransaction {
        let base = pending?.transaction ?? model.makePendingTransaction()
        let timestamp = pending?.startedAt ?? base.timestamp
        let status: WalletTransaction.TransferStatus
        if isFailed {
            status = transferStatus
        } else if showsOnChainSuccess || isSent {
            status = .confirmed
        } else {
            status = .processing
        }

        return WalletTransaction(
            id: base.id,
            kind: .sent,
            title: base.title,
            subtitle: base.subtitle,
            amountUSDT: base.amountUSDT,
            dayLabel: base.dayLabel,
            txID: base.txID,
            fromAddress: base.fromAddress,
            toAddress: base.toAddress,
            timestamp: timestamp,
            transferStatus: status
        )
    }

    private var headlineText: String {
        if isFailed { return L10n.Send.failed }
        if showsHandoffSuccess { return L10n.TransferProof.transferSent }
        if isPreparingHandoff { return L10n.Send.processingPreparing }
        return L10n.Send.processing
    }

    private var subtitleText: String {
        if case .failed(let message) = transferStatus {
            return SendErrorPresenter.userFacingRelayText(message)
        }
        if showsOnChainSuccess {
            return L10n.TransferProof.confirmedOnNetwork
        }
        if showsHandoffSuccess {
            return L10n.Send.processingBackgroundSafe
        }
        if isPreparingHandoff {
            return sanitizedStepMessage(pending?.stepMessage) ?? L10n.Send.processingPreparing
        }
        return sanitizedStepMessage(pending?.stepMessage) ?? L10n.TransferProof.processingOnNetwork
    }

    /// Network prep runs on the review slider; processing should not repeat those steps.
    private func sanitizedStepMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.contains("preparing network")
            || lower.contains("waiting for network")
            || lower.contains("requesting network energy")
            || lower.contains("network bandwidth")
            || lower.contains("activating address")
            || lower.contains("activation confirmation")
            || lower.contains("checking address")
            || lower.contains("checking network")
        {
            return "Sending USDT…"
        }
        return trimmed
    }

    var body: some View {
        ZStack(alignment: .top) {
            MeshSelectWalletSheetBackground()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        statusHero
                            .padding(.top, 36)

                        VStack(spacing: 8) {
                            Text(headlineText)
                                .font(MeshTheme.Typography.sans(size: 22, weight: .semibold))
                                .foregroundStyle(MeshTheme.Colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(subtitleText)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(MeshTheme.Colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .animation(.easeInOut(duration: 0.25), value: subtitleText)
                        }

                        MeshTransferProofCard(transaction: displayTransaction, style: .standard)
                            .animation(.easeInOut(duration: 0.28), value: displayTransaction.transferStatus)
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)
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
        .interactiveDismissDisabled(false)
        .meshEdgeDismissDisabled(false)
        .meshNavigationPopDisabled(isPreparingHandoff)
        .task {
            if let sendID = model.activePendingSendID,
               let item = pending,
               item.id == sendID,
               !sendService.isSafeToCloseApp(for: item),
               !sendService.isHandoffRunning
            {
                sendService.startHandoffForPendingSend(model: model)
            }
            await refreshOnChainVerification()
            await pollHandoffUntilSettled()
        }
        .onChange(of: pending?.handoffRegistered) { _, _ in
            Task { await refreshOnChainVerification() }
        }
        .onChange(of: pending?.transaction.txID) { _, _ in
            Task { await refreshOnChainVerification() }
        }
        .onChange(of: pending?.transaction.transferStatus) { _, _ in
            Task { await refreshOnChainVerification() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .meshInAppBrowserSheet(url: $inAppBrowserURL)
    }

    @ViewBuilder
    private var footerActions: some View {
        if isPreparingHandoff {
            VStack(spacing: 10) {
                keepOpenCallout
                Text(L10n.Send.processingPreparingHint)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        } else {
            VStack(spacing: 12) {
                if isFailed {
                    MeshSecondaryButton(title: L10n.Common.contact) {
                        inAppBrowserURL = MeshAppLinks.contactPage
                    }
                }
                MeshPrimaryButton(
                    title: L10n.Common.done,
                    action: closeAndExit
                )
            }
        }
    }

    private var keepOpenCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.iphone")
                .font(MeshTheme.Typography.icon(size: 18, weight: .medium))
                .foregroundStyle(MeshTheme.Colors.accent)
                .frame(width: 24, height: 24)

            Text(L10n.Send.keepOpen)
                .font(MeshTheme.Typography.sans(size: 15, weight: .regular))
                .foregroundStyle(MeshTheme.Colors.textPrimary.opacity(0.92))
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            MeshTheme.Colors.accent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.fieldRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MeshTheme.Metrics.fieldRadius, style: .continuous)
                .stroke(MeshTheme.Colors.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func closeAndExit() {
        sendService.clearCurrent()
        onClose()
    }

    private func refreshOnChainVerification() async {
        guard let item = pending else {
            onChainVerified = false
            return
        }
        if case .confirmed = item.transaction.transferStatus {
            if await TronUSDTService.verifyOutgoingUSDTTransfer(
                txID: item.transaction.txID,
                fromAddress: item.transaction.fromAddress,
                toAddress: item.recipientAddress,
                amount: item.amountUSDT,
                notBefore: item.startedAt
            ) != nil {
                onChainVerified = true
            } else {
                onChainVerified = false
            }
        } else if case .failed = item.transaction.transferStatus,
                  TronUSDTService.isPlausibleTronTransactionID(item.transaction.txID)
        {
            await sendService.tryConfirmBroadcastTransfer(id: item.id)
            if case .confirmed? = sendService.current?.transaction.transferStatus {
                onChainVerified = true
            } else {
                onChainVerified = false
            }
        } else if case .processing = item.transaction.transferStatus,
                  TronUSDTService.isPlausibleTronTransactionID(item.transaction.txID)
        {
            await sendService.tryConfirmBroadcastTransfer(id: item.id)
            if case .confirmed? = sendService.current?.transaction.transferStatus {
                onChainVerified = true
            } else {
                onChainVerified = false
            }
        } else {
            onChainVerified = false
        }
    }

    private func pollHandoffUntilSettled() async {
        guard MeshNetworkSponsorship.isRelayConfigured else { return }
        let deadline = Date().addingTimeInterval(10 * 60)
        while !Task.isCancelled, Date() < deadline {
            if isFailed || showsHandoffSuccess {
                return
            }

            if pending == nil, !sendService.isHandoffRunning {
                return
            }

            if let sendID = model.activePendingSendID,
               let item = pending,
               item.id == sendID,
               !sendService.isSafeToCloseApp(for: item),
               !sendService.isHandoffRunning
            {
                sendService.startHandoffForPendingSend(model: model)
            }

            await sendService.refreshWorkerQueuedSendStatuses()

            if let status = pending?.transaction.transferStatus {
                switch status {
                case .confirmed, .failed:
                    return
                case .processing:
                    break
                }
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    @ViewBuilder
    private var statusHero: some View {
        if isFailed {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 88, height: 88)
                Circle()
                    .stroke(Color.orange.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 88, height: 88)
                Image(systemName: "xmark")
                    .font(MeshTheme.Typography.icon(size: 30, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }
        } else if showsHandoffSuccess {
            ZStack {
                Circle()
                    .fill(MeshTheme.Colors.success.opacity(0.16))
                    .frame(width: 88, height: 88)
                Circle()
                    .stroke(MeshTheme.Colors.success.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark")
                    .font(MeshTheme.Typography.icon(size: 34, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.success)
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            ZStack {
                Circle()
                    .fill(MeshTheme.Colors.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                Circle()
                    .stroke(MeshTheme.Colors.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 88, height: 88)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(MeshTheme.Colors.accent)
                    .scaleEffect(1.1)
            }
        }
    }
}
