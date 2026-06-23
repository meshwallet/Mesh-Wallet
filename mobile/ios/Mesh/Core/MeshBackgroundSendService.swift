import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Runs USDT send after the user leaves the submit screen; updates pending transfer state for detail UI.
@MainActor
final class MeshBackgroundSendService: ObservableObject {
    static let shared = MeshBackgroundSendService()

    struct PendingTransfer: Identifiable {
        let id: String
        var transaction: WalletTransaction
        var stepMessage: String
        let walletID: String
        let recipientAddress: String
        let amountText: String
        let amountUSDT: Decimal
        let isPrivateSendMode: Bool
        let sendPrivacyMode: MeshPrivateSendMode
        /// Locked spend slot for this transfer (survives app restart).
        let selectedSendSlotIndex: UInt32
        let startedAt: Date
        var networkFeeCollected: Bool
        var workerQueued: Bool
        var handoffRegistered: Bool
        var presignedFeeTxJSON: String?
        var handoffResumeJSON: String?
        /// Raw on-chain USDT for the spend address when this send began.
        var chainUSDTAtStart: Decimal?

        init(
            id: String,
            transaction: WalletTransaction,
            stepMessage: String,
            walletID: String,
            recipientAddress: String,
            amountText: String,
            amountUSDT: Decimal,
            isPrivateSendMode: Bool,
            sendPrivacyMode: MeshPrivateSendMode,
            selectedSendSlotIndex: UInt32 = 0,
            startedAt: Date,
            networkFeeCollected: Bool = false,
            workerQueued: Bool = false,
            handoffRegistered: Bool = false,
            presignedFeeTxJSON: String? = nil,
            handoffResumeJSON: String? = nil,
            chainUSDTAtStart: Decimal? = nil
        ) {
            self.id = id
            self.transaction = transaction
            self.stepMessage = stepMessage
            self.walletID = walletID
            self.recipientAddress = recipientAddress
            self.amountText = amountText
            self.amountUSDT = amountUSDT
            self.isPrivateSendMode = isPrivateSendMode
            self.sendPrivacyMode = sendPrivacyMode
            self.selectedSendSlotIndex = selectedSendSlotIndex
            self.startedAt = startedAt
            self.networkFeeCollected = networkFeeCollected
            self.workerQueued = workerQueued
            self.handoffRegistered = handoffRegistered
            self.presignedFeeTxJSON = presignedFeeTxJSON
            self.handoffResumeJSON = handoffResumeJSON
            self.chainUSDTAtStart = chainUSDTAtStart
        }

        init(record: PendingSendRecord) {
            id = record.id
            walletID = record.walletID
            recipientAddress = record.recipientAddress
            amountText = record.amountText
            amountUSDT = Decimal(string: record.amountUSDT) ?? 0
            isPrivateSendMode = record.isPrivateSendMode
            sendPrivacyMode = MeshPrivateSendMode(rawValue: record.sendPrivacyMode) ?? .standard
            selectedSendSlotIndex = record.selectedSendSlotIndex ?? 0
            stepMessage = record.stepMessage
            startedAt = record.startedAt
            networkFeeCollected = record.hasCollectedNetworkFee
            workerQueued = record.isWorkerQueued
            handoffRegistered = record.isHandoffRegistered
            presignedFeeTxJSON = record.presignedFeeTxJSON
            handoffResumeJSON = record.handoffResumeJSON
            if let raw = record.chainUSDTAtStart?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty
            {
                chainUSDTAtStart = Decimal(string: raw)
            } else {
                chainUSDTAtStart = nil
            }

            let status: WalletTransaction.TransferStatus
            switch record.status {
            case .processing:
                status = .processing
            case .confirmed:
                status = .confirmed
            case .failed:
                status = .failed(record.failedMessage ?? "Send failed")
            }

            transaction = WalletTransaction(
                id: record.id,
                kind: .sent,
                title: "Sent",
                subtitle: TronUSDTService.shortAddress(record.toAddress),
                amountUSDT: Decimal(string: record.amountUSDT) ?? 0,
                dayLabel: record.dayLabel,
                txID: record.txID,
                fromAddress: record.fromAddress,
                toAddress: record.toAddress,
                timestamp: record.timestamp,
                transferStatus: status
            )
        }

        fileprivate func toRecord() -> PendingSendRecord {
            let status: PendingSendRecord.Status
            var failedMessage: String?
            switch transaction.transferStatus {
            case .processing:
                status = .processing
            case .confirmed:
                status = .confirmed
            case .failed(let message):
                status = .failed
                failedMessage = message
            }

            return PendingSendRecord(
                id: id,
                walletID: walletID,
                recipientAddress: recipientAddress,
                amountText: amountText,
                amountUSDT: NSDecimalNumber(decimal: amountUSDT).stringValue,
                isPrivateSendMode: isPrivateSendMode,
                sendPrivacyMode: sendPrivacyMode.rawValue,
                stepMessage: stepMessage,
                startedAt: startedAt,
                txID: transaction.txID,
                fromAddress: transaction.fromAddress,
                toAddress: transaction.toAddress,
                dayLabel: transaction.dayLabel,
                timestamp: transaction.timestamp,
                status: status,
                failedMessage: failedMessage,
                networkFeeCollected: networkFeeCollected,
                workerQueued: workerQueued,
                handoffRegistered: handoffRegistered,
                presignedFeeTxJSON: presignedFeeTxJSON,
                handoffResumeJSON: handoffResumeJSON,
                selectedSendSlotIndex: selectedSendSlotIndex,
                chainUSDTAtStart: chainUSDTAtStart.map { NSDecimalNumber(decimal: $0).stringValue }
            )
        }
    }

    @Published private(set) var current: PendingTransfer?
    /// In-flight / recent sends shown in activity until confirmed on-chain.
    @Published private(set) var trackedTransfers: [PendingTransfer] = []
    @Published private(set) var shouldRefreshWalletHistory = false
    /// Backend flagged wallet after send confirmed on-chain without user→treasury fee.
    @Published private(set) var isFeeDelinquent = false
    /// Sign + register (or private on-device route) is running — not tied to send UI lifetime.
    @Published private(set) var isHandoffRunning = false

    var feeDelinquentUserMessage: String {
        "A previous send fee was not collected. Open the app and complete the pending fee before sending again."
    }

    private var sendTask: Task<Void, Never>?
    private var sendTaskGeneration = 0
    /// Prevents overlapping broadcasts for the same pending send id.
    private var broadcastInProgressSendID: String?
    /// Exclusive lock for sign + register + worker wait (prevents duplicate TRX spend on worker).
    private var handoffTask: Task<Void, Error>?
    private var retainedModel: SendFlowViewModel?
    private var activeSendID: String?
    /// Pinned for the duration of `handoffTask` — must not follow wallet picker changes.
    private var handoffPinnedSendID: String?
    private var handoffPinnedWalletID: String?

    /// How long we keep trying to resume / match an in-flight send (matches pre-signed fee validity).
    private static let pendingSendTTL: TimeInterval = 24 * 60 * 60
    /// Direct on-device send with no tx id — fail instead of leaving "Sending" for hours.
    private static let directSendNoTxFailAfter: TimeInterval = 90
    /// Direct sends can spend 2–3 min on activation + Energy for new recipients.
    private static let orphanPendingHoldAge: TimeInterval = 200
    private static let workerStatusPollStale: TimeInterval = 8 * 60
    private static let directWorkerUnreachableFailAfter: TimeInterval = 5 * 60
    private static let workerUnreachableFailAfter: TimeInterval = 25 * 60
    private static let workerEphemeralRetryAfter: TimeInterval = 45
    private static let workerQueuedGiveUpAfter: TimeInterval = 45 * 60
    /// Worker handoff: keep retrying activation/energy errors before showing failure in Activity.
    private static let workerHandoffRetryGracePeriod: TimeInterval = 5 * 60
    private static let abandonedSendMessage =
        "Send did not finish in time. If your USDT balance is unchanged, you can try again."
    private static let workerUnreachableMessage =
        "Mesh could not confirm this send. Check your USDT balance — if funds are still there, try again."

    private init() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeProcessingSendsIfNeeded()
            }
        }
        #endif
        NotificationCenter.default.addObserver(
            forName: .meshActiveWalletDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restoreForActiveWallet()
            }
        }
    }

    /// Retries in-flight sends after foreground return.
    func resumeProcessingSendsIfNeeded() {
        if handoffTask != nil { return }
        guard sendTask == nil,
              let inFlight = trackedTransfers.first(where: { $0.transaction.isProcessing })
        else { return }

        activeSendID = inFlight.id
        current = inFlight
        let model = SendFlowViewModel(replaying: inFlight)
        retainedModel = model

        if MeshNetworkSponsorship.isRelayConfigured {
            if inFlight.handoffRegistered {
                Task { await self.refreshWorkerQueuedSendStatuses() }
                return
            }
            resumeIncompleteHandoff(model: model)
            return
        }

        Task {
            if await completeIfAlreadyOnChain(item: inFlight) { return }
            guard sendTask == nil else { return }
            sendTaskGeneration += 1
            runSendTask(for: inFlight, model: model, generation: sendTaskGeneration)
        }
    }

    private func resumeIncompleteHandoff(model: SendFlowViewModel) {
        startHandoffForPendingSend(model: model)
    }

    /// Re-sign and re-register when the worker could not broadcast before tx expiration.
    private func attemptResignExpiredHandoff(item: PendingTransfer) async {
        guard handoffTask == nil, sendTask == nil else { return }
        activeSendID = item.id
        current = item
        mutateTransfer(id: item.id) { pending in
            pending.handoffRegistered = false
            pending.workerQueued = false
            pending.stepMessage = "Refreshing signature…"
            let tx = pending.transaction
            pending.transaction = WalletTransaction(
                id: tx.id,
                kind: tx.kind,
                title: L10n.Send.processing,
                subtitle: tx.subtitle,
                amountUSDT: tx.amountUSDT,
                dayLabel: tx.dayLabel,
                txID: "",
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                timestamp: tx.timestamp,
                transferStatus: .processing
            )
        }
        startHandoffForPendingSend(model: SendFlowViewModel(replaying: item))
    }

    /// True once sign + register finished and worker can finish without the app.
    func isSafeToCloseApp(for pending: PendingTransfer?) -> Bool {
        guard let pending, pending.transaction.isProcessing else { return true }
        if MeshNetworkSponsorship.isRelayConfigured {
            return pending.handoffRegistered
        }
        if !pending.transaction.txID.isEmpty { return true }
        return pending.workerQueued
    }

    /// Poll relay for worker-queued sends (updates Activity + releases balance hold on failure).
    func refreshWorkerQueuedSendStatuses() async {
        await syncWorkerQueuedSendStatuses()
    }

    var historyTransactions: [WalletTransaction] {
        WalletHomeViewModel.dedupeActivityPending(trackedTransfers.map(\.transaction))
    }

    /// On-chain USDT total (HD: sum of five receive slots 0…4).
    func chainUSDTBalance(
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) async throws -> Decimal {
        if MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) {
            return try await MeshPrivacyService.fiveReceiveSlotsUSDTTotal(walletID: walletID)
        }
        let address: String
        if let walletID,
           let wallet = MeshWalletRegistry.wallet(id: walletID),
           !wallet.address.isEmpty
        {
            address = wallet.address
        } else {
            address = try TronUSDTService.currentAddress()
        }
        guard let balance = await TronUSDTService.fetchUSDTBalance(address: address) else {
            throw TronAPIError.broadcastFailed(
                "Could not load USDT balance. Check your connection and try again."
            )
        }
        return balance
    }

    /// Spendable balance = on-chain total minus in-flight send holds (releases orphan holds first).
    func spendableUSDT(
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) async throws -> Decimal {
        restoreForActiveWallet()
        releaseOrphanPendingHolds()
        guard let walletID else { return 0 }
        let chain = try await chainUSDTBalance(walletID: walletID)
        let hold = pendingBalanceHold(for: walletID, chainBalance: chain)
        return max(0, chain - hold)
    }

    /// Fails processing rows that never registered with the worker and are not actively handing off.
    func releaseOrphanPendingHolds() {
        guard sendTask == nil, handoffTask == nil else { return }

        let now = Date()
        for item in trackedTransfers {
            guard item.transaction.isProcessing else { continue }
            guard !item.handoffRegistered, !item.workerQueued else { continue }
            if hasBroadcastTxID(item) {
                Task { await self.tryConfirmBroadcastTransfer(id: item.id) }
                continue
            }
            let age = now.timeIntervalSince(item.startedAt)
            if age >= Self.directSendNoTxFailAfter {
                failTransfer(
                    id: item.id,
                    message: resolvedFailureMessage(
                        for: item,
                        fallback: Self.abandonedSendMessage
                    )
                )
                continue
            }
            if item.id == activeSendID, age < Self.orphanPendingHoldAge {
                continue
            }
            if age < Self.orphanPendingHoldAge {
                continue
            }
            if isLikelyInFlightNetworkPrepare(item) {
                continue
            }
            failTransfer(
                id: item.id,
                message: resolvedFailureMessage(
                    for: item,
                    fallback: Self.abandonedSendMessage
                )
            )
        }
    }

    /// When the send UI closes, keep in-flight on-device sends running — do not mark failed while broadcasting.
    func abandonEphemeralPendingSendIfNeeded() {
        clearCurrent()
        if let activeSendID,
           !trackedTransfers.contains(where: { $0.id == activeSendID })
        {
            self.activeSendID = trackedTransfers.first { $0.transaction.isProcessing }?.id
        }
    }

    /// USDT reserved from displayed balance while sends are in flight (amount + fee until settled).
    func pendingBalanceHold(for walletID: String, chainBalance: Decimal? = nil) -> Decimal {
        pendingBalanceHold(for: walletID, spendFromAddress: "", chainBalance: chainBalance)
    }

    /// Hold for a specific receive/send address (HD slot 1…4 — not only main).
    func pendingBalanceHold(
        for walletID: String,
        spendFromAddress: String,
        chainBalance: Decimal? = nil
    ) -> Decimal {
        let normalized = spendFromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return trackedTransfers
            .filter { $0.walletID == walletID }
            .filter { normalized.isEmpty || TronAddressCodec.matches($0.transaction.fromAddress, normalized) }
            .reduce(Decimal.zero) { partial, item in
                partial + effectivePendingBalanceHold(for: item, chainBalance: chainBalance)
            }
    }

    private func effectivePendingBalanceHold(
        for item: PendingTransfer,
        chainBalance: Decimal?
    ) -> Decimal {
        let raw = rawPendingBalanceHold(for: item)
        guard raw > 0, let chain = chainBalance else { return raw }
        guard case .processing = item.transaction.transferStatus else { return raw }
        guard let snapshot = item.chainUSDTAtStart else { return raw }
        let tolerance = Decimal(string: "0.000001") ?? 0
        let expectedAfterSend = snapshot - item.amountUSDT
        if chain <= expectedAfterSend + tolerance {
            return 0
        }
        return raw
    }

    /// On-chain balance snapshot when the send started (used to release hold once Tron reflects the debit).
    private func attachChainUSDTAtStart(to item: inout PendingTransfer, model: SendFlowViewModel) {
        guard item.chainUSDTAtStart == nil else { return }
        let spendFrom = item.transaction.fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let priorHold: Decimal
        if spendFrom.isEmpty {
            priorHold = pendingBalanceHold(for: item.walletID)
        } else {
            priorHold = pendingBalanceHold(for: item.walletID, spendFromAddress: spendFrom)
        }
        item.chainUSDTAtStart = model.availableUSDT + priorHold
    }

    private func rawPendingBalanceHold(for item: PendingTransfer) -> Decimal {
        switch item.transaction.transferStatus {
        case .failed:
            return 0
        case .processing:
            if !MeshSendFees.chargesOnChainFee {
                return item.amountUSDT
            }
            let fee = MeshSendFees.networkFee(
                isPrivateSend: item.isPrivateSendMode,
                mode: item.sendPrivacyMode
            )
            if !item.isPrivateSendMode, MeshSendFees.directFeeBundledInMainTx {
                return item.amountUSDT + fee
            }
            let feeHold = item.networkFeeCollected ? 0 : fee
            return item.amountUSDT + feeHold
        case .confirmed:
            guard !item.networkFeeCollected else { return 0 }
            return MeshSendFees.networkFee(
                isPrivateSend: item.isPrivateSendMode,
                mode: item.sendPrivacyMode
            )
        }
    }

    /// True while there is pending send work that requires history reconciliation.
    var needsHistoryReconcile: Bool {
        trackedTransfers.contains { item in
            if item.transaction.isProcessing { return true }
            return !item.networkFeeCollected && !item.transaction.txID.isEmpty
        }
    }

    func restoreForActiveWallet() {
        guard let walletID = MeshWalletRegistry.activeWalletID else {
            trackedTransfers = []
            current = nil
            activeSendID = nil
            return
        }
        trackedTransfers = MeshPendingSendStore.load()
            .filter { $0.walletID == walletID }
            .map(PendingTransfer.init(record:))
        dedupeDuplicateActivityTransfers()
        recoverFalseFailedTransfers()

        if let pinned = handoffPinnedSendID,
           handoffTask != nil,
           handoffPinnedWalletID != walletID
        {
            current = trackedTransfers.first { $0.transaction.isProcessing }
            activeSendID = current?.id
            healMislabeledWorkerQueuedTransfers()
            return
        }

        if let activeSendID,
           let item = trackedTransfers.first(where: { $0.id == activeSendID }) {
            current = item
        } else {
            current = trackedTransfers.first { $0.transaction.isProcessing }
            activeSendID = current?.id
        }
        healMislabeledWorkerQueuedTransfers()
    }

    func pendingTransfer(id: String) -> PendingTransfer? {
        resolvePendingTransfer(id: id)
    }

    /// Clears `workerQueued` when register succeeded but the worker never started the network step.
    private func healMislabeledWorkerQueuedTransfers() {
        for index in trackedTransfers.indices {
            var item = trackedTransfers[index]
            guard item.transaction.isProcessing,
                  item.workerQueued,
                  item.handoffRegistered,
                  !item.isPrivateSendMode,
                  item.transaction.txID.isEmpty
            else { continue }
            item.workerQueued = false
            trackedTransfers[index] = item
            if current?.id == item.id {
                current = item
            }
            persist(item)
        }
    }

    /// Match persisted processing sends with chain history; resume or fail stale ones.
    func reconcileAfterHistoryLoad(chain: [WalletTransaction]) async {
        restoreForActiveWallet()

        // 1. Collect fee and confirm any processing items already visible in chain.
        for index in trackedTransfers.indices {
            guard trackedTransfers[index].transaction.isProcessing else { continue }
            if let match = Self.chainMatch(for: trackedTransfers[index], in: chain) {
                await completeMatchedSend(
                    id: trackedTransfers[index].id,
                    txID: match.txID,
                    timestamp: match.timestamp
                )
            }
        }

        // 2. Worker queue: poll relay status for handoff-complete sends.
        await syncWorkerQueuedSendStatuses()

        // 2b. Undo "Sent" rows that never reached the chain (stale worker / false match).
        await reconcilePhantomConfirmedSends(chain: chain)

        // 3. Retry fee for confirmed items whose fee step was missed (do this BEFORE pruning).
        await retryUncollectedNetworkFees()

        // 4. Remove confirmed items that are now in chain (fee already handled above).
        pruneTrackedTransfersPresentInChain(chain)

        if handoffTask != nil { return }
        guard sendTask == nil else { return }

        guard let inFlight = trackedTransfers.first(where: { $0.transaction.isProcessing }) else { return }

        if inFlight.workerQueued {
            await syncWorkerQueuedSendStatuses()
            if Self.chainMatch(for: inFlight, in: chain) != nil {
                return
            }
            let retryChain = await fetchRecentChain(limit: 80)
            if let match = Self.chainMatch(for: inFlight, in: retryChain) {
                await completeMatchedSend(id: inFlight.id, txID: match.txID, timestamp: match.timestamp)
                pruneTrackedTransfersPresentInChain(retryChain)
            }
            return
        }

        if MeshNetworkSponsorship.isRelayConfigured, inFlight.isPrivateSendMode {
            if inFlight.handoffRegistered || inFlight.workerQueued {
                await finishHandoffIfNeeded(model: SendFlowViewModel(replaying: inFlight))
            } else {
                resumeIncompleteHandoff(model: SendFlowViewModel(replaying: inFlight))
            }
            return
        }

        if Self.chainMatch(for: inFlight, in: chain) != nil { return }

        let age = Date().timeIntervalSince(inFlight.startedAt)

        if !hasBroadcastTxID(inFlight),
           !inFlight.handoffRegistered,
           age >= Self.directSendNoTxFailAfter
        {
            failTransfer(
                id: inFlight.id,
                message: resolvedFailureMessage(for: inFlight, fallback: Self.abandonedSendMessage)
            )
            return
        }

        if age < 30 {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let retryChain = await fetchRecentChain(limit: 80)
            if let match = Self.chainMatch(for: inFlight, in: retryChain) {
                await completeMatchedSend(id: inFlight.id, txID: match.txID, timestamp: match.timestamp)
                pruneTrackedTransfersPresentInChain(retryChain)
                return
            }
        }

        if age >= Self.pendingSendTTL {
            let finalChain = await fetchRecentChain(limit: 120)
            if let match = Self.chainMatch(for: inFlight, in: finalChain) {
                await completeMatchedSend(id: inFlight.id, txID: match.txID, timestamp: match.timestamp)
                pruneTrackedTransfersPresentInChain(finalChain)
                return
            }
            failTransfer(
                id: inFlight.id,
                message: resolvedFailureMessage(for: inFlight, fallback: Self.abandonedSendMessage)
            )
            return
        }

        let model = SendFlowViewModel(replaying: inFlight)
        activeSendID = inFlight.id
        current = inFlight
        retainedModel = model
        Task {
            if await completeIfAlreadyOnChain(item: inFlight) { return }
            guard sendTask == nil else { return }
            sendTaskGeneration += 1
            runSendTask(for: inFlight, model: model, generation: sendTaskGeneration)
        }
    }

    /// Retries Mesh fee collection for sends that reached chain before the fee step ran.
    private func syncWorkerQueuedSendStatuses() async {
        let processing = allInFlightTransfers().filter {
            $0.transaction.isProcessing
                && ($0.workerQueued || $0.handoffRegistered)
        }

        for item in processing {
            let age = Date().timeIntervalSince(item.startedAt)
            let giveUpAfter = await workerNetworkGiveUpAfter(for: item)

            if let match = await findChainMatch(for: item) {
                await completeMatchedSend(id: item.id, txID: match.txID, timestamp: match.timestamp)
                continue
            }

            guard let status = await MeshSendFeeObligationService.fetchSendStatus(obligationId: item.id) else {
                if age >= Self.workerEphemeralRetryAfter,
                   !item.isPrivateSendMode,
                   item.handoffRegistered
                {
                    await MeshSendFeeObligationService.nudgeWorkerContinue(
                        obligationId: item.id,
                        resumeJSON: item.handoffResumeJSON
                    )
                    mutateTransfer(id: item.id) { pending in
                        pending.stepMessage = "Mesh is processing your send…"
                    }
                }
                let unreachableAfter = item.isPrivateSendMode
                    ? Self.workerUnreachableFailAfter
                    : Self.directWorkerUnreachableFailAfter
                if age >= unreachableAfter,
                   await findChainMatch(for: item) == nil
                {
                    failTransfer(id: item.id, message: Self.workerUnreachableMessage)
                }
                continue
            }

            if status.status == "expired_needs_resign"
                || status.lastError?.localizedCaseInsensitiveContains("EXPIRED_NEEDS_RESIGN") == true
            {
                if age < 12 * 60 {
                    await attemptResignExpiredHandoff(item: item)
                } else {
                    failTransfer(
                        id: item.id,
                        message: "Send signature expired. Please try again."
                    )
                }
                continue
            }

            if status.status == "failed",
               let message = status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty
            {
                if shouldSurfaceWorkerFailure(status, age: age, maxGrace: giveUpAfter) {
                    failTransfer(
                        id: item.id,
                        message: Self.workerFailureDisplayMessage(message)
                    )
                    continue
                }
                await MeshSendFeeObligationService.nudgeWorkerContinue(
                    obligationId: item.id,
                    resumeJSON: item.handoffResumeJSON
                )
                mutateTransfer(id: item.id) { pending in
                    pending.stepMessage = "Mesh is processing your send…"
                }
            }

            if item.handoffRegistered {
                if Self.workerNetworkStarted(from: status) {
                    if !item.workerQueued {
                        mutateTransfer(id: item.id) { pending in
                            pending.workerQueued = true
                            pending.stepMessage = "Processing"
                        }
                    }
                } else if item.workerQueued,
                          status.status == "queued",
                          (status.currentStepIndex ?? 0) == 0,
                          status.networkStartedAtMs == nil
                {
                    mutateTransfer(id: item.id) { pending in
                        pending.workerQueued = false
                    }
                } else if status.status == "failed", shouldSurfaceWorkerFailure(status, age: age, maxGrace: giveUpAfter) {
                    let message = status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines)
                    failTransfer(
                        id: item.id,
                        message: (message?.isEmpty == false)
                            ? message!
                            : "Send failed on the network. Please try again."
                    )
                    continue
                } else if age >= giveUpAfter,
                          status.status == "queued",
                          (status.currentStepIndex ?? 0) == 0,
                          status.networkStartedAtMs == nil
                {
                    await MeshSendFeeObligationService.nudgeWorkerContinue(
                        obligationId: item.id,
                        resumeJSON: item.handoffResumeJSON
                    )
                    failTransfer(
                        id: item.id,
                        message: workerStartFailMessage
                    )
                    continue
                }
            }

            guard item.workerQueued || Self.workerNetworkStarted(from: status) else { continue }

            switch status.status {
            case "pending":
                if status.hasSignedMain == false || age >= 3 * 60 {
                    failTransfer(
                        id: item.id,
                        message: "Send did not reach Mesh network. Check your USDT balance and try again."
                    )
                }
            case "settled", "send_confirmed_fee_pending":
                if let txID = status.mainTxID,
                   !txID.isEmpty,
                   TronUSDTService.isPlausibleTronTransactionID(txID)
                {
                    await completeMatchedSend(id: item.id, txID: txID, timestamp: Date())
                } else {
                    mutateTransfer(id: item.id) { pending in
                        pending.stepMessage = "Sending on network…"
                    }
                }
            case "failed":
                if shouldSurfaceWorkerFailure(status, age: age, maxGrace: giveUpAfter) {
                    let message = status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines)
                    failTransfer(
                        id: item.id,
                        message: (message?.isEmpty == false)
                            ? Self.workerFailureDisplayMessage(message!)
                            : "Send failed on the network. Please try again."
                    )
                } else {
                    mutateTransfer(id: item.id) { pending in
                        pending.stepMessage = "Mesh is retrying on network…"
                    }
                }
            case "processing_queue", "queued":
                mutateTransfer(id: item.id) { pending in
                    pending.stepMessage = workerStepMessage(from: status, item: item)
                }
            default:
                break
            }

            if age >= giveUpAfter,
               status.mainTxID?.isEmpty != false,
               await findChainMatch(for: item) == nil
            {
                failTransfer(id: item.id, message: Self.abandonedSendMessage)
            }
        }
    }

    private func allInFlightTransfers() -> [PendingTransfer] {
        var byID: [String: PendingTransfer] = [:]
        for item in trackedTransfers {
            byID[item.id] = item
        }
        for record in MeshPendingSendStore.load() where record.status == .processing {
            if byID[record.id] == nil {
                byID[record.id] = PendingTransfer(record: record)
            }
        }
        return Array(byID.values)
    }

    private func resolvePendingTransfer(id: String) -> PendingTransfer? {
        if let item = trackedTransfers.first(where: { $0.id == id }) {
            return item
        }
        guard let record = MeshPendingSendStore.load().first(where: { $0.id == id }) else {
            return nil
        }
        return PendingTransfer(record: record)
    }

    private func workerNetworkGiveUpAfter(for item: PendingTransfer) async -> TimeInterval {
        let from = item.transaction.fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty else { return Self.workerHandoffRetryGracePeriod }
        if await TronAPIService.isAccountActivated(address: from) {
            return Self.directSendNoTxFailAfter
        }
        return Self.workerHandoffRetryGracePeriod
    }

    private func clearHandoffPins() {
        handoffPinnedSendID = nil
        handoffPinnedWalletID = nil
    }

    private func workerStepMessage(
        from status: MeshSendFeeObligationService.SendStatusResponse,
        item: PendingTransfer
    ) -> String {
        if item.isPrivateSendMode || status.isPrivateSend == true {
            let total = max(status.totalSteps ?? 0, 1)
            let step = min(max((status.currentStepIndex ?? 0) + 1, 1), total)
            if let label = status.lastStepLabel, !label.isEmpty {
                return "Private route \(step)/\(total): \(label)…"
            }
            return "Private route step \(step)/\(total)…"
        }
        return "Sending on network…"
    }

    private static func workerNetworkStarted(
        from status: MeshSendFeeObligationService.SendStatusResponse
    ) -> Bool {
        if let txID = status.mainTxID, !txID.isEmpty { return true }
        switch status.status {
        case "send_confirmed_fee_pending", "settled":
            return true
        case "processing_queue":
            if status.isPrivateSend == true {
                let step = status.currentStepIndex ?? 0
                return step >= 1 || !(status.lastStepTxID?.isEmpty ?? true)
            }
            return status.networkStartedAtMs != nil
        case "queued":
            if status.isPrivateSend == true {
                let step = status.currentStepIndex ?? 0
                return step >= 1 || !(status.lastStepTxID?.isEmpty ?? true)
            }
            return status.networkStartedAtMs != nil
        default:
            return false
        }
    }

    private func shouldSurfaceWorkerFailure(
        _ status: MeshSendFeeObligationService.SendStatusResponse,
        age: TimeInterval,
        maxGrace: TimeInterval = workerHandoffRetryGracePeriod
    ) -> Bool {
        let error = status.lastError?.lowercased() ?? ""
        if isPermanentWorkerHandoffError(error) {
            return true
        }

        if age < maxGrace,
           isTransientWorkerHandoffError(error)
        {
            return false
        }

        let attempts = status.queueAttempts ?? 0
        if attempts >= 8 { return true }

        if age >= Self.workerStatusPollStale, attempts >= 2 {
            return true
        }

        return false
    }

    private func isPermanentWorkerHandoffError(_ lower: String) -> Bool {
        lower.contains("mismatch")
            || lower.contains("missing signature")
            || lower.contains("not a usdt")
            || lower.contains("not a transfer")
            || lower.contains("expired")
    }

    private static func workerFailureDisplayMessage(_ raw: String) -> String {
        let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return "Send failed on the network. Please try again."
        }
        let lower = message.lowercased()
        if lower.contains("resource insufficient")
            || lower.contains("out_of_energy")
            || lower.contains("out of energy")
            || lower.contains("bandwidth")
            || lower.contains("energy")
            || lower.contains("not ready")
            || lower.contains("activate")
            || lower.contains("not exist")
        {
            return message
        }
        if lower.contains("not enough usdt") || lower.contains("balance") {
            return "\(message) Check your USDT balance before sending again."
        }
        return message
    }

    private func isTransientWorkerHandoffError(_ lower: String) -> Bool {
        if lower.isEmpty { return true }
        if isPermanentWorkerHandoffError(lower) { return false }
        return lower.contains("activate")
            || lower.contains("not exist")
            || lower.contains("does not exist")
            || lower.contains("energy")
            || lower.contains("not ready")
            || lower.contains("bandwidth")
            || lower.contains("tronnrg")
            || lower.contains("verify")
            || lower.contains("timeout")
            || lower.contains("busy")
            || lower.contains("http")
    }

    private func findChainMatch(for item: PendingTransfer) async -> WalletTransaction? {
        guard let address = try? TronUSDTService.currentAddress(),
              let history = try? await TronUSDTService.fetchTransactions(address: address, limit: 80)
        else { return nil }
        let chain = history.map { WalletTransaction(tron: $0) }
        return Self.chainMatch(for: item, in: chain)
    }

    private func mutateTransfer(id: String, mutate: (inout PendingTransfer) -> Void) {
        if let index = trackedTransfers.firstIndex(where: { $0.id == id }) {
            var item = trackedTransfers[index]
            mutate(&item)
            trackedTransfers[index] = item
            if current?.id == id { current = item }
            persist(item)
            return
        }
        guard var item = resolvePendingTransfer(id: id) else { return }
        mutate(&item)
        persist(item)
    }

    private func retryUncollectedNetworkFees() async {
        guard MeshSendFees.enforcesOnChainSendFees else { return }
        // Snapshot: trackedTransfers may mutate during async work.
        let ids = trackedTransfers
            .filter { !$0.networkFeeCollected && !$0.transaction.txID.isEmpty }
            .map(\.id)

        for id in ids {
            guard let index = trackedTransfers.firstIndex(where: { $0.id == id }) else { continue }
            guard !trackedTransfers[index].networkFeeCollected else { continue }

            let item = trackedTransfers[index]

            if item.isPrivateSendMode,
               !item.transaction.txID.isEmpty,
               let funding = try? await SendFlowViewModel(replaying: item).privacyFundingSource(
                   requiredAmount: MeshSendFees.networkFee(
                       isPrivateSend: true,
                       mode: item.sendPrivacyMode
                   )
               ),
               await MeshSendFeeObligationService.settleSendFee(
                   obligationId: item.id,
                   mainTxID: item.transaction.txID,
                   fundingAddress: funding.address
               )
            {
                if let i = trackedTransfers.firstIndex(where: { $0.id == id }) {
                    trackedTransfers[i].networkFeeCollected = true
                    persist(trackedTransfers[i])
                    activeSendID = id
                    notifyBackendFeeSettled()
                }
                continue
            }

            if !item.isPrivateSendMode,
               await collectDirectWorkerFee(for: item)
            {
                if let i = trackedTransfers.firstIndex(where: { $0.id == id }) {
                    trackedTransfers[i].networkFeeCollected = true
                    persist(trackedTransfers[i])
                    activeSendID = id
                    notifyBackendFeeSettled()
                }
                continue
            }

            // Check if fee already landed on-chain to avoid double charge.
            if await hasFeeTransferOnChain(for: item) {
                if let i = trackedTransfers.firstIndex(where: { $0.id == id }) {
                    trackedTransfers[i].networkFeeCollected = true
                    persist(trackedTransfers[i])
                    activeSendID = id
                    notifyBackendFeeSettled()
                }
                continue
            }

            let model = sendModel(for: item)
            do {
                try await model.collectPendingNetworkFee()
                if let i = trackedTransfers.firstIndex(where: { $0.id == id }) {
                    trackedTransfers[i].networkFeeCollected = true
                    persist(trackedTransfers[i])
                    activeSendID = id
                    notifyBackendFeeSettled()
                }
                shouldRefreshWalletHistory = true
            } catch {
                // Fee failed — will retry next reconcile. Transfer stays visible.
            }
        }
    }

    func refreshFeeStatus() async {
        guard MeshSendFees.enforcesOnChainSendFees else {
            isFeeDelinquent = false
            return
        }
        guard let address = try? TronUSDTService.currentAddress() else {
            isFeeDelinquent = false
            return
        }
        let status = await MeshSendFeeObligationService.fetchFeeStatus(userAddress: address)
        isFeeDelinquent = status?.delinquent == true
    }

    /// Creates a pending row before the handoff screen runs (sign + register with worker).
    func prepareForHandoff(model: SendFlowViewModel) {
        if MeshSendFees.enforcesOnChainSendFees, isFeeDelinquent { return }

        let activeWalletID = MeshWalletRegistry.activeWalletID ?? WalletAccountStore.mainWalletID
        if handoffTask != nil,
           let pinnedWallet = handoffPinnedWalletID,
           pinnedWallet != activeWalletID
        {
            return
        }

        sendTask?.cancel()
        sendTask = nil
        handoffTask?.cancel()
        handoffTask = nil

        model.lockSendSlotForExecution()
        var item = buildPendingTransfer(from: model, stepMessage: "Starting…")
        attachChainUSDTAtStart(to: &item, model: model)
        activeSendID = item.id
        upsertTracked(item)
        current = item
        retainedModel = model
        shouldRefreshWalletHistory = false
        persist(item)
    }

    /// Starts sign + register in a detached task. Safe to close the app once `isSafeToCloseApp` is true.
    func startHandoffForPendingSend(model: SendFlowViewModel) {
        launchHandoffIfNeeded(
            model: model,
            waitForNetworkStart: false,
            onProgress: { [weak self] message in
                self?.updateStepMessage(message)
            }
        )
    }

    /// Signs transfers, registers with worker; does not broadcast from the device.
    func executeHandoff(
        model: SendFlowViewModel,
        waitForNetworkStart: Bool = true,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws {
        launchHandoffIfNeeded(
            model: model,
            waitForNetworkStart: waitForNetworkStart,
            onProgress: onProgress
        )
        guard let handoffTask else {
            if let item = current, isSafeToCloseApp(for: item) { return }
            if let id = activeSendID ?? current?.id {
                failTransfer(
                    id: id,
                    message: "Could not start send. Please try again."
                )
            }
            throw TronAPIError.broadcastFailed("Could not start send. Please try again.")
        }
        try await handoffTask.value
        if let error = handoffFailureForUI() {
            throw error
        }
    }

    private func handoffFailureForUI() -> Error? {
        guard let item = current else { return nil }
        if item.handoffRegistered { return nil }
        if case .failed(let message) = item.transaction.transferStatus {
            return TronAPIError.broadcastFailed(message)
        }
        guard item.transaction.isProcessing else { return nil }
        let message = item.stepMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty || message == "Starting…" {
            return TronAPIError.broadcastFailed("Could not start send. Please try again.")
        }
        return TronAPIError.broadcastFailed(message)
    }

    private func launchHandoffIfNeeded(
        model: SendFlowViewModel,
        waitForNetworkStart: Bool,
        onProgress: @escaping @MainActor (String) -> Void
    ) {
        if let item = current, isSafeToCloseApp(for: item) { return }
        if let pinned = handoffPinnedSendID,
           handoffTask != nil,
           pinned != model.activePendingSendID
        {
            return
        }
        if handoffTask != nil { return }

        #if canImport(UIKit)
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MeshSendHandoff") {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        #endif

        isHandoffRunning = true
        handoffTask = Task { @MainActor in
            defer {
                isHandoffRunning = false
                handoffTask = nil
                clearHandoffPins()
                #if canImport(UIKit)
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                #endif
            }
            do {
                if handoffPinnedSendID == nil {
                    if current == nil {
                        prepareForHandoff(model: model)
                    }
                    if let id = model.activePendingSendID ?? current?.id ?? activeSendID,
                       let item = resolvePendingTransfer(id: id)
                    {
                        handoffPinnedSendID = id
                        handoffPinnedWalletID = item.walletID
                        activeSendID = id
                        current = item
                    }
                }
                try await performHandoffWork(
                    model: model,
                    waitForNetworkStart: waitForNetworkStart,
                    onProgress: onProgress
                )
                if MeshSendFees.collectsSendFee(isPrivateSend: model.isPrivateSendMode),
                   let item = current,
                   !item.isPrivateSendMode
                {
                    Task { await self.collectDirectWorkerFeeIfNeeded() }
                }
            } catch is CancellationError {
                if let id = activeSendID {
                    markHandoffFailed(id: id, message: "Send was cancelled.")
                }
                throw CancellationError()
            } catch {
                let message = SendErrorPresenter.message(for: error)
                if let id = activeSendID {
                    markHandoffFailed(id: id, message: message)
                }
                throw error
            }
        }
    }

    /// Throws when handoff did not register with the worker after executeHandoff awaited the handoff task.
    func verifyHandoffStarted() throws {
        guard let item = current else {
            throw TronAPIError.broadcastFailed("Send session was lost. Please try again.")
        }
        guard item.handoffRegistered else {
            let detail = item.stepMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty, detail != "Starting…" {
                throw TronAPIError.broadcastFailed(detail)
            }
            throw TronAPIError.broadcastFailed("Could not start send. Please try again.")
        }
    }

    /// Keeps in-flight sends alive when the app backgrounds or the user leaves the processing screen.
    func prepareForBackgroundContinuation() {
        guard let inFlight = trackedTransfers.first(where: { $0.transaction.isProcessing }) else { return }

        if MeshNetworkSponsorship.isRelayConfigured {
            if inFlight.handoffRegistered || inFlight.workerQueued {
                Task {
                    await MeshSendFeeObligationService.nudgeWorkerContinue(
                        obligationId: inFlight.id,
                        resumeJSON: inFlight.handoffResumeJSON
                    )
                }
                Task { await refreshWorkerQueuedSendStatuses() }
                return
            }
            let model = retainedModel ?? SendFlowViewModel(replaying: inFlight)
            activeSendID = inFlight.id
            retainedModel = model
            startHandoffForPendingSend(model: model)
            return
        }

        guard sendTask == nil else { return }
        let model = retainedModel ?? SendFlowViewModel(replaying: inFlight)
        activeSendID = inFlight.id
        retainedModel = model
        Task {
            if await completeIfAlreadyOnChain(item: inFlight) { return }
            guard sendTask == nil else { return }
            sendTaskGeneration += 1
            runSendTask(for: inFlight, model: model, generation: sendTaskGeneration)
        }
    }

    /// After register succeeds, keep polling worker even if the app backgrounds or closes the send UI.
    private func markWorkerQueuedAfterHandoffRegister() {
        guard let item = current, item.handoffRegistered else { return }
        mutateActiveTransfer { pending in
            pending.workerQueued = true
            if pending.stepMessage == "Starting…" || pending.stepMessage == "Mesh accepted your send…" {
                pending.stepMessage = "Processing on Mesh…"
            }
        }
    }

    /// Poll worker until network start when register already succeeded (no re-sign / re-register).
    private func finishHandoffIfNeeded(model: SendFlowViewModel) async {
        guard let inFlight = trackedTransfers.first(where: { $0.transaction.isProcessing }),
              inFlight.handoffRegistered,
              !inFlight.workerQueued
        else { return }

        activeSendID = inFlight.id
        current = inFlight
        retainedModel = model

        do {
            try await executeHandoff(
                model: model,
                waitForNetworkStart: MeshSendFees.collectsSendFee(isPrivateSend: model.isPrivateSendMode)
            ) { [weak self] message in
                self?.updateStepMessage(message)
            }
        } catch {
            guard !SendErrorPresenter.isTransientNetworkError(error) else { return }
            markHandoffFailed(id: inFlight.id, message: SendErrorPresenter.message(for: error))
        }
    }

    private func performHandoffWork(
        model: SendFlowViewModel,
        waitForNetworkStart: Bool,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws {
        if MeshSendFees.enforcesOnChainSendFees, isFeeDelinquent {
            throw TronAPIError.broadcastFailed(feeDelinquentUserMessage)
        }

        let pinnedID = handoffPinnedSendID
            ?? model.activePendingSendID
            ?? activeSendID
            ?? current?.id

        if current == nil, pinnedID == nil {
            prepareForHandoff(model: model)
        }

        guard let sendID = pinnedID ?? model.activePendingSendID ?? current?.id,
              var item = resolvePendingTransfer(id: sendID)
        else {
            throw TronAPIError.broadcastFailed("Send session was lost. Please try again.")
        }

        handoffPinnedSendID = sendID
        handoffPinnedWalletID = item.walletID
        activeSendID = sendID
        current = item

        if item.handoffRegistered {
            return
        }

        if model.isResumingPersistedSend {
            await syncHandoffRegisteredFromWorker(obligationId: item.id)
            if let refreshed = resolvePendingTransfer(id: sendID) {
                item = refreshed
                current = refreshed
            }
        }

        if !item.handoffRegistered {
            await onProgress("Preparing your transfer…")
            let source = try await model.directSpendSourceForHandoff()
            let directSpendSource = source
            mutateTransfer(id: sendID) { pending in
                pending.transaction = model.sentTransaction(
                    txID: pending.transaction.txID,
                    fromAddress: source.address
                )
                if pending.chainUSDTAtStart == nil {
                    attachChainUSDTAtStart(to: &pending, model: model)
                }
            }

            let handoff = try await MeshSendHandoffService.performHandoff(
                model: model,
                obligationID: item.id,
                directSpendSource: directSpendSource
            ) { message in
                Task { @MainActor in
                    self.updateStepMessage(message)
                    onProgress(message)
                }
            }

            if let signedFee = handoff.signedFeeTxJSON, !signedFee.isEmpty {
                model.attachPresignedNetworkFee(signedFee)
                mutateTransfer(id: sendID) { pending in
                    pending.presignedFeeTxJSON = signedFee
                }
            }

            let userAddress = handoff.userAddress
            mutateTransfer(id: sendID) { pending in
                let tx = pending.transaction
                pending.transaction = WalletTransaction(
                    id: tx.id,
                    kind: tx.kind,
                    title: tx.title,
                    subtitle: tx.subtitle,
                    amountUSDT: tx.amountUSDT,
                    dayLabel: tx.dayLabel,
                    txID: tx.txID,
                    fromAddress: userAddress,
                    toAddress: tx.toAddress,
                    timestamp: tx.timestamp,
                    transferStatus: tx.transferStatus
                )
            }

            let fee = MeshSendFees.workerRegistrationFee(isPrivateSend: false, mode: .standard)

            if let resumeJSON = MeshSendFeeObligationService.encodeHandoffResumeJSON(
                handoff: handoff,
                userAddress: userAddress,
                recipientAddress: item.recipientAddress,
                amountUSDT: item.amountUSDT,
                feeUSDT: fee,
                startedAt: item.startedAt
            ) {
                mutateTransfer(id: sendID) { pending in
                    pending.handoffResumeJSON = resumeJSON
                }
            }

            let registerResult = try await MeshSendFeeObligationService.registerQueuedSend(
                handoff: handoff,
                userAddress: userAddress,
                recipientAddress: item.recipientAddress,
                amountUSDT: item.amountUSDT,
                feeUSDT: fee,
                startedAt: item.startedAt
            )

            guard registerResult.queued || registerResult.mainTxID != nil else {
                throw TronAPIError.broadcastFailed(
                    "Send service is outdated. Update Mesh relay, then try again."
                )
            }

            if let mainTxID = registerResult.mainTxID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !mainTxID.isEmpty
            {
                mutateTransfer(id: sendID) { pending in
                    pending.handoffRegistered = true
                    pending.workerQueued = true
                    pending.networkFeeCollected = MeshSendFees.initialNetworkFeeCollected(
                        isPrivateSend: handoff.isPrivateSend
                    )
                    pending.stepMessage = "Processing on Mesh…"
                    let tx = pending.transaction
                    pending.transaction = WalletTransaction(
                        id: tx.id,
                        kind: tx.kind,
                        title: L10n.Send.processing,
                        subtitle: tx.subtitle,
                        amountUSDT: tx.amountUSDT,
                        dayLabel: tx.dayLabel,
                        txID: TronUSDTService.isPlausibleTronTransactionID(mainTxID) ? mainTxID : "",
                        fromAddress: tx.fromAddress,
                        toAddress: tx.toAddress,
                        timestamp: tx.timestamp,
                        transferStatus: .processing
                    )
                }
                Task { await self.syncWorkerQueuedSendStatuses() }
                return
            }

            mutateTransfer(id: sendID) { pending in
                pending.handoffRegistered = true
                pending.workerQueued = false
                pending.stepMessage = "Processing on Mesh…"
            }
            Task { await self.syncWorkerQueuedSendStatuses() }
        }
    }

    private var workerStartFailAfter: TimeInterval {
        Self.workerHandoffRetryGracePeriod
    }

    private var workerStartFailMessage: String {
        MeshSendFees.collectsSendFee(isPrivateSend: false)
            ? "Send did not start on the network. Please try again."
            : "Mesh could not start this send. Check your USDT balance and try again."
    }

    /// If the app crashed after register, recover state from worker without re-registering.
    private func syncHandoffRegisteredFromWorker(obligationId: String) async {
        guard let status = await MeshSendFeeObligationService.fetchSendStatus(obligationId: obligationId),
              status.hasSignedMain != false
        else { return }

        let acceptedStatuses: Set<String> = [
            "queued",
            "processing_queue",
            "send_confirmed_fee_pending",
            "settled",
        ]
        if let workerStatus = status.status, acceptedStatuses.contains(workerStatus) {
            mutateTransfer(id: obligationId) { pending in
                pending.handoffRegistered = true
            }
        }
    }

    func beginSend(model: SendFlowViewModel) {
        if MeshSendFees.enforcesOnChainSendFees, isFeeDelinquent {
            return
        }

        model.lockSendSlotForExecution()
        var item = buildPendingTransfer(from: model, stepMessage: "Sending USDT…")
        attachChainUSDTAtStart(to: &item, model: model)

        if activeSendID == item.id, sendTask != nil {
            return
        }

        if activeSendID != item.id {
            sendTask?.cancel()
            sendTask = nil
        }

        activeSendID = item.id
        upsertTracked(item)
        current = item
        retainedModel = model
        shouldRefreshWalletHistory = false
        persist(item)

        sendTaskGeneration += 1
        runSendTask(for: item, model: model, generation: sendTaskGeneration)
    }

    func clearCurrent() {
        current = nil
    }

    func markHandoffFailed(id: String, message: String) {
        failTransfer(id: id, message: message)
    }

    func acknowledgeHistoryRefresh() {
        shouldRefreshWalletHistory = false
    }

    /// Drops tracked items that now appear in Tron history (by tx id).
    func pruneTrackedTransfersPresentInChain(_ chain: [WalletTransaction]) {
        let chainTxIDs = Set(chain.map(\.txID).filter { !$0.isEmpty })
        let removedIDs = trackedTransfers.compactMap { item -> String? in
            guard case .confirmed = item.transaction.transferStatus else { return nil }
            if chainTxIDs.contains(item.transaction.txID) { return item.id }
            if WalletHomeViewModel.pendingSupersededByChain(item.transaction, chain: chain) {
                return item.id
            }
            return nil
        }
        trackedTransfers.removeAll { item in
            guard case .confirmed = item.transaction.transferStatus else { return false }
            if chainTxIDs.contains(item.transaction.txID) { return true }
            return WalletHomeViewModel.pendingSupersededByChain(item.transaction, chain: chain)
        }
        for id in removedIDs {
            MeshPendingSendStore.remove(id: id)
        }
        if let activeSendID,
           !trackedTransfers.contains(where: { $0.id == activeSendID }) {
            self.activeSendID = trackedTransfers.first { $0.transaction.isProcessing }?.id
            current = trackedTransfers.first { $0.id == self.activeSendID }
        }
    }

    private func runSendTask(
        for item: PendingTransfer,
        model: SendFlowViewModel,
        generation: Int
    ) {
        #if canImport(UIKit)
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MeshSend") {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        #endif

        sendTask = Task { @MainActor in
            defer {
                #if canImport(UIKit)
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                #endif
                if broadcastInProgressSendID == item.id {
                    broadcastInProgressSendID = nil
                }
                if sendTaskGeneration == generation {
                    retainedModel = nil
                }
                sendTask = nil
            }

            let sendModel = retainedModel ?? model
            retainedModel = sendModel

            if await completeIfAlreadyOnChain(item: item) {
                return
            }

            guard sendModel.passesInFlightSendValidation() else {
                await markFailed(sendModel.inFlightSendValidationError())
                return
            }

            let fee = MeshSendFees.networkFee(
                isPrivateSend: sendModel.isPrivateSendMode,
                mode: sendModel.sendPrivacyMode
            )
            if MeshSendFees.registersFeeWithWorkerBeforeSend(isPrivateSend: sendModel.isPrivateSendMode),
               fee > 0,
               !sendModel.isResumingPersistedSend,
               sendModel.presignedFeeTxJSON == nil
            {
                updateStepMessage("Preparing send fee…")
                try? await sendModel.preparePresignedNetworkFee()
            }

            if MeshSendFees.registersFeeWithWorkerBeforeSend(isPrivateSend: sendModel.isPrivateSendMode),
               let userAddress = try? sendModel.feeRegistrationUserAddress()
            {
                await MeshSendFeeObligationService.registerSendFee(
                    id: item.id,
                    userAddress: userAddress,
                    recipientAddress: item.recipientAddress,
                    amountUSDT: item.amountUSDT,
                    feeUSDT: fee,
                    startedAt: item.startedAt,
                    signedFeeTxJSON: sendModel.presignedFeeTxJSON
                )
            }

            if await completeIfAlreadyOnChain(item: item) {
                return
            }

            if Task.isCancelled {
                await reconcileCancelledSend(item: item)
                return
            }

            guard sendTaskGeneration == generation else { return }

            broadcastInProgressSendID = item.id

            let maxAttempts = 3
            var lastError: Error?
            for attempt in 0..<maxAttempts {
                guard sendTaskGeneration == generation else { return }
                if Task.isCancelled {
                    await reconcileCancelledSend(item: item)
                    return
                }

                do {
                    let outcome = try await sendModel.sendUSDT(
                        statusUpdate: { [weak self] message in
                            guard !Task.isCancelled else { return }
                            self?.updateStepMessage(message)
                        },
                        chainGuardNotBefore: item.startedAt
                    )
                    persistBroadcastTxID(id: item.id, txID: outcome.result.txID)

                    if outcome.networkFeeCollected {
                        markNetworkFeeCollected()
                    }
                    markSent(txID: outcome.result.txID)
                    return
                } catch is CancellationError {
                    await reconcileCancelledSend(item: item)
                    return
                } catch {
                    lastError = error

                    if let verified = await verifyTransferWithRetries(
                        txID: item.transaction.txID,
                        fromAddress: item.transaction.fromAddress,
                        toAddress: item.recipientAddress,
                        amount: item.amountUSDT,
                        notBefore: item.startedAt,
                        maxAttempts: 4
                    ) {
                        await finishConfirmedTransfer(id: item.id, verified: verified)
                        return
                    }

                    if await completeIfAlreadyOnChain(item: item) {
                        return
                    }

                    let stage = trackedTransfers.first(where: { $0.id == item.id })?.stepMessage
                    let detail = SendErrorPresenter.detailedMessage(for: error, stage: stage)

                    if SendErrorPresenter.isTransientNetworkError(error), attempt < maxAttempts - 1 {
                        updateStepMessage(detail)
                        try? await Task.sleep(nanoseconds: UInt64(2 + attempt) * 1_000_000_000)
                        continue
                    }

                    await markFailed(detail)
                    return
                }
            }

            if let lastError {
                let stage = trackedTransfers.first(where: { $0.id == item.id })?.stepMessage
                await markFailed(SendErrorPresenter.detailedMessage(for: lastError, stage: stage))
            }
        }
    }

    private func updateStepMessage(_ message: String) {
        mutateActiveTransfer { pending in
            pending.stepMessage = message
        }
    }

    private func markNetworkFeeCollected() {
        mutateActiveTransfer { pending in
            pending.networkFeeCollected = true
        }
        notifyBackendFeeSettled()
    }

    private func notifyBackendFeeSettled() {
        guard MeshSendFees.enforcesOnChainSendFees else { return }
        let obligationID = activeSendID
        Task {
            guard let address = try? TronUSDTService.currentAddress() else { return }
            await MeshSendFeeObligationService.clearDelinquent(
                userAddress: address,
                obligationId: obligationID
            )
            await refreshFeeStatus()
        }
    }

    /// Persists a broadcast tx id immediately so retries/resume cannot sign again.
    private func persistBroadcastTxID(id: String, txID: String) {
        guard TronUSDTService.isPlausibleTronTransactionID(txID) else { return }
        mutateTransfer(id: id) { pending in
            let tx = pending.transaction
            guard tx.txID.isEmpty else { return }
            pending.transaction = WalletTransaction(
                id: tx.id,
                kind: tx.kind,
                title: tx.title,
                subtitle: tx.subtitle,
                amountUSDT: tx.amountUSDT,
                dayLabel: tx.dayLabel,
                txID: txID,
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                timestamp: tx.timestamp,
                transferStatus: .processing
            )
        }
    }

    /// Returns true when an outbound transfer for this pending send is already on Tron.
    @discardableResult
    private func completeIfAlreadyOnChain(item: PendingTransfer) async -> Bool {
        if hasBroadcastTxID(item) {
            await tryConfirmBroadcastTransfer(id: item.id)
            if let index = trackedTransfers.firstIndex(where: { $0.id == item.id }),
               case .confirmed = trackedTransfers[index].transaction.transferStatus
            {
                return true
            }
        }

        let chain = await fetchRecentChainForSpend(
            fromAddress: item.transaction.fromAddress,
            limit: 80
        )
        guard let match = Self.chainMatch(for: item, in: chain) else { return false }
        await completeMatchedSend(id: item.id, txID: match.txID, timestamp: match.timestamp)
        return true
    }

    /// After task cancellation, confirm an in-flight broadcast instead of leaving a retryable row.
    private func reconcileCancelledSend(item: PendingTransfer) async {
        if hasBroadcastTxID(item) {
            await tryConfirmBroadcastTransfer(id: item.id)
            return
        }

        if let verified = await verifyTransferWithRetries(
            txID: "",
            fromAddress: item.transaction.fromAddress,
            toAddress: item.recipientAddress,
            amount: item.amountUSDT,
            notBefore: item.startedAt,
            maxAttempts: 8
        ) {
            await finishConfirmedTransfer(id: item.id, verified: verified)
            return
        }

        if await completeIfAlreadyOnChain(item: item) {
            return
        }

        updateStepMessage("Waiting for connection…")
    }

    /// USDT is already on-chain; collect Mesh fee if the app closed before that step.
    private func completeMatchedSend(id: String, txID: String, timestamp: Date) async {
        guard let index = trackedTransfers.firstIndex(where: { $0.id == id }) else { return }
        let item = trackedTransfers[index]

        if let verified = await verifyTransferWithRetries(
            txID: txID,
            fromAddress: item.transaction.fromAddress,
            toAddress: item.recipientAddress,
            amount: item.amountUSDT,
            notBefore: item.startedAt
        ) {
            await finishConfirmedTransfer(id: id, verified: verified)
            return
        }

        if TronUSDTService.isPlausibleTronTransactionID(txID) {
            mutateTransfer(id: id) { pending in
                pending.stepMessage = "Waiting for network confirmation…"
                let tx = pending.transaction
                pending.transaction = WalletTransaction(
                    id: tx.id,
                    kind: tx.kind,
                    title: L10n.Send.processing,
                    subtitle: tx.subtitle,
                    amountUSDT: tx.amountUSDT,
                    dayLabel: tx.dayLabel,
                    txID: txID,
                    fromAddress: tx.fromAddress,
                    toAddress: tx.toAddress,
                    timestamp: tx.timestamp,
                    transferStatus: .processing
                )
            }
            return
        }
    }

    private func finishConfirmedTransfer(
        id: String,
        verified: TronUSDTTransaction,
        item: PendingTransfer? = nil,
        index: Int? = nil
    ) async {
        let resolvedIndex = index ?? trackedTransfers.firstIndex(where: { $0.id == id })
        guard let resolvedIndex else { return }
        let resolvedItem = item ?? trackedTransfers[resolvedIndex]

        let confirmedTxID = verified.txID
        let confirmedAt = verified.timestamp

        if !resolvedItem.networkFeeCollected {
            if await hasFeeTransferOnChain(for: resolvedItem) {
                trackedTransfers[resolvedIndex].networkFeeCollected = true
                persist(trackedTransfers[resolvedIndex])
            } else if await collectDirectWorkerFee(for: resolvedItem) {
                trackedTransfers[resolvedIndex].networkFeeCollected = true
                persist(trackedTransfers[resolvedIndex])
                notifyBackendFeeSettled()
            } else {
                let model = sendModel(for: resolvedItem)
                updateStepMessage("Paying send fee…")
                do {
                    try await model.collectPendingNetworkFee { [weak self] message in
                        self?.updateStepMessage(message)
                    }
                    trackedTransfers[resolvedIndex].networkFeeCollected = true
                    persist(trackedTransfers[resolvedIndex])
                    notifyBackendFeeSettled()
                } catch {
                    // Keep transfer visible; fee can retry on next app open / history refresh.
                    updateStepMessage("Paying send fee…")
                }
            }
        }

        confirmTransfer(id: id, txID: confirmedTxID, timestamp: confirmedAt)
    }

    private func hasBroadcastTxID(_ item: PendingTransfer) -> Bool {
        TronUSDTService.isPlausibleTronTransactionID(item.transaction.txID)
    }

    private func verifyTransferWithRetries(
        txID: String,
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        notBefore: Date,
        maxAttempts: Int = 20
    ) async -> TronUSDTTransaction? {
        for attempt in 0..<maxAttempts {
            if let verified = await TronUSDTService.verifyOutgoingUSDTTransfer(
                txID: txID,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amount,
                notBefore: notBefore
            ) {
                return verified
            }
            guard attempt < maxAttempts - 1 else { break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return nil
    }

    func tryConfirmBroadcastTransfer(id: String, preferredTxID: String? = nil) async {
        guard let index = trackedTransfers.firstIndex(where: { $0.id == id }) else { return }
        let item = trackedTransfers[index]
        if case .confirmed = item.transaction.transferStatus { return }

        let txID = preferredTxID ?? item.transaction.txID
        guard TronUSDTService.isPlausibleTronTransactionID(txID) else { return }

        if let verified = await verifyTransferWithRetries(
            txID: txID,
            fromAddress: item.transaction.fromAddress,
            toAddress: item.recipientAddress,
            amount: item.amountUSDT,
            notBefore: item.startedAt
        ) {
            await finishConfirmedTransfer(id: id, verified: verified)
        }
    }

    /// Corrects rows marked failed while the USDT transfer is already on Tron.
    private func recoverFalseFailedTransfers() {
        for item in trackedTransfers {
            guard case .failed = item.transaction.transferStatus else { continue }
            if hasBroadcastTxID(item) {
                Task { await tryConfirmBroadcastTransfer(id: item.id) }
                continue
            }
            Task {
                if await completeIfAlreadyOnChain(item: item) {
                    shouldRefreshWalletHistory = true
                }
            }
        }
    }

    /// Reverts confirmed UI rows that are not present as outbound USDT on Tron.
    private func reconcilePhantomConfirmedSends(chain: [WalletTransaction]) async {
        let chainTxIDs = Set(chain.map(\.txID).filter { !$0.isEmpty })

        for item in trackedTransfers {
            guard case .confirmed = item.transaction.transferStatus else { continue }

            let txID = item.transaction.txID
            if !txID.isEmpty, chainTxIDs.contains(txID) {
                continue
            }

            if await TronUSDTService.verifyOutgoingUSDTTransfer(
                txID: txID,
                fromAddress: item.transaction.fromAddress,
                toAddress: item.recipientAddress,
                amount: item.amountUSDT,
                notBefore: item.startedAt
            ) != nil {
                continue
            }

            mutateTransfer(id: item.id) { pending in
                pending.stepMessage = "Mesh is processing your send…"
                let tx = pending.transaction
                pending.transaction = WalletTransaction(
                    id: tx.id,
                    kind: .sent,
                    title: L10n.Send.processing,
                    subtitle: tx.subtitle,
                    amountUSDT: tx.amountUSDT,
                    dayLabel: tx.dayLabel,
                    txID: "",
                    fromAddress: tx.fromAddress,
                    toAddress: tx.toAddress,
                    timestamp: tx.timestamp,
                    transferStatus: .processing
                )
                pending.workerQueued = false
            }
        }

        if trackedTransfers.contains(where: { $0.transaction.isProcessing }) {
            await syncWorkerQueuedSendStatuses()
        }
    }

    private func markSent(txID: String) {
        guard retainedModel != nil else { return }

        if let id = activeSendID, TronUSDTService.isPlausibleTronTransactionID(txID) {
            updateStepMessage(L10n.Send.sent)
            Task { await tryConfirmBroadcastTransfer(id: id, preferredTxID: txID) }
        }
        shouldRefreshWalletHistory = true
    }

    /// Reverts a single in-memory "Sent" row that is not on Tron (e.g. stale worker id).
    @MainActor
    func revertPhantomConfirmed(id: String) async {
        guard let index = trackedTransfers.firstIndex(where: { $0.id == id }) else { return }
        let item = trackedTransfers[index]
        guard case .confirmed = item.transaction.transferStatus else { return }

        let txID = item.transaction.txID
        if await TronUSDTService.verifyOutgoingUSDTTransfer(
            txID: txID,
            fromAddress: item.transaction.fromAddress,
            toAddress: item.recipientAddress,
            amount: item.amountUSDT,
            notBefore: item.startedAt
        ) != nil {
            return
        }

        mutateTransfer(id: id) { pending in
            pending.stepMessage = "Mesh is processing your send…"
            let tx = pending.transaction
            pending.transaction = WalletTransaction(
                id: tx.id,
                kind: .sent,
                title: L10n.Send.processing,
                subtitle: tx.subtitle,
                amountUSDT: tx.amountUSDT,
                dayLabel: tx.dayLabel,
                txID: "",
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                timestamp: tx.timestamp,
                transferStatus: .processing
            )
            pending.workerQueued = false
        }
    }

    private func markFailed(_ message: String) async {
        if let id = activeSendID,
           let item = trackedTransfers.first(where: { $0.id == id })
        {
            if hasBroadcastTxID(item) {
                await tryConfirmBroadcastTransfer(id: id)
                return
            }
            if let verified = await verifyTransferWithRetries(
                txID: item.transaction.txID,
                fromAddress: item.transaction.fromAddress,
                toAddress: item.recipientAddress,
                amount: item.amountUSDT,
                notBefore: item.startedAt
            ) {
                await finishConfirmedTransfer(id: id, verified: verified)
                return
            }
        }

        guard let model = retainedModel else {
            if let id = activeSendID {
                failTransfer(id: id, message: message)
            }
            return
        }

        if let id = activeSendID,
           let item = trackedTransfers.first(where: { $0.id == id })
        {
            failTransfer(id: id, message: message)
        }
        shouldRefreshWalletHistory = true
    }

    private func confirmTransfer(id: String, txID: String, timestamp: Date) {
        guard let index = trackedTransfers.firstIndex(where: { $0.id == id }) else { return }
        purgeDuplicateActivityTransfers(keepingID: id)
        // Read the latest version (may already have networkFeeCollected = true).
        var item = trackedTransfers[index]
        item.transaction = WalletTransaction(
            id: txID,
            kind: .sent,
            title: "Sent",
            subtitle: TronUSDTService.shortAddress(item.recipientAddress),
            amountUSDT: item.amountUSDT,
            dayLabel: item.transaction.dayLabel,
            txID: txID,
            fromAddress: item.transaction.fromAddress,
            toAddress: item.recipientAddress,
            timestamp: timestamp,
            transferStatus: .confirmed
        )
        item.stepMessage = "Sent"
        // Preserve networkFeeCollected that may have been set by completeMatchedSend.
        item.networkFeeCollected = trackedTransfers[index].networkFeeCollected
        trackedTransfers[index] = item
        if current?.id == id { current = item }
        persist(item)
        shouldRefreshWalletHistory = true
    }

    private func isLikelyInFlightNetworkPrepare(_ item: PendingTransfer) -> Bool {
        let step = item.stepMessage.lowercased()
        return step.contains("preparing")
            || step.contains("waiting for network")
            || step.contains("new address")
            || step.contains("activating")
            || step.contains("network resources")
            || step.contains("retrying network")
    }

    private func isInformativeFailureStep(_ step: String) -> Bool {
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower == "processing" || lower == "starting…" || lower == "sent" {
            return false
        }
        return lower.contains("network")
            || lower.contains("energy")
            || lower.contains("bandwidth")
            || lower.contains("mesh")
            || lower.contains("tron")
            || lower.contains("prepare")
            || lower.contains("waiting")
            || lower.contains("activat")
            || lower.contains("http")
            || lower.contains("connection")
            || lower.contains("timeout")
            || lower.contains("timed out")
            || lower.contains("failed")
            || lower.contains("error")
            || lower.contains("ops wallet")
            || lower.contains("busy")
            || lower.contains("relay")
            || lower.contains("broadcast")
            || lower.contains("cancelled")
            || lower.contains("canceled")
    }

    private func isProgressStepMessage(_ step: String) -> Bool {
        let lower = step.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if lower == "processing" || lower == "starting…" || lower == "sent" || lower == L10n.Send.processing.lowercased() {
            return true
        }
        return lower.contains("preparing network")
            || lower.contains("waiting for network")
            || lower.contains("preparing send fee")
            || lower.contains("paying send fee")
            || lower.contains("sending usdt")
            || lower.contains("sending on network")
            || lower.contains("processing on mesh")
            || lower.contains("mesh is processing")
            || lower.contains("mesh is retrying")
            || lower.contains("connecting to mesh")
            || lower.contains("mesh accepted")
            || lower.contains("private route")
    }

    private func resolvedFailureMessage(for item: PendingTransfer, fallback: String) -> String {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallback.isEmpty {
            return trimmedFallback
        }
        let step = item.stepMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !step.isEmpty, !isProgressStepMessage(step) {
            return step
        }
        return "Send failed."
    }

    private func failTransfer(id: String, message: String) {
        guard let index = trackedTransfers.firstIndex(where: { $0.id == id }) else { return }
        var item = trackedTransfers[index]
        if hasBroadcastTxID(item) {
            Task { await tryConfirmBroadcastTransfer(id: id) }
            return
        }
        let display = resolvedFailureMessage(for: item, fallback: message)
        item.transaction.transferStatus = .failed(display)
        item.stepMessage = display
        trackedTransfers[index] = item
        if current?.id == id { current = item }
        persist(item)
        shouldRefreshWalletHistory = true
    }

    private func removeTracked(id: String) {
        trackedTransfers.removeAll { $0.id == id }
        MeshPendingSendStore.remove(id: id)
        if current?.id == id { current = nil }
        if activeSendID == id { activeSendID = nil }
    }

    private func mutateActiveTransfer(_ mutate: (inout PendingTransfer) -> Void) {
        guard let id = activeSendID,
              let index = trackedTransfers.firstIndex(where: { $0.id == id })
        else { return }

        var item = trackedTransfers[index]
        mutate(&item)
        trackedTransfers[index] = item
        if current?.id == id {
            current = item
        }
        persist(item)
    }

    private func buildPendingTransfer(
        from model: SendFlowViewModel,
        stepMessage: String
    ) -> PendingTransfer {
        let walletID = MeshWalletRegistry.activeWalletID ?? WalletAccountStore.mainWalletID
        let recipient = model.recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = model.recipientPayoutUSDT

        if let existing = matchingInFlightTransfer(
            walletID: walletID,
            recipient: recipient,
            amountUSDT: amount
        ) {
            model.adoptPendingSendRecordID(existing.id)
            var item = existing
            item.stepMessage = stepMessage
            return item
        }

        let pending = model.makePendingTransaction()
        return PendingTransfer(
            id: pending.id,
            transaction: pending,
            stepMessage: stepMessage,
            walletID: walletID,
            recipientAddress: recipient,
            amountText: model.amountText,
            amountUSDT: amount,
            isPrivateSendMode: false,
            sendPrivacyMode: .standard,
            selectedSendSlotIndex: model.lockedSendSlotIndex ?? model.selectedSendSlotIndex,
            startedAt: Date(),
            networkFeeCollected: MeshSendFees.initialNetworkFeeCollected(isPrivateSend: false),
            workerQueued: false,
            handoffRegistered: false
        )
    }

    private func matchingInFlightTransfer(
        walletID: String,
        recipient: String,
        amountUSDT: Decimal
    ) -> PendingTransfer? {
        let tolerance = Decimal(string: "0.000001") ?? 0
        let normalizedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        return trackedTransfers
            .filter { $0.walletID == walletID && isReusableInFlightTransfer($0) }
            .sorted { $0.startedAt > $1.startedAt }
            .first { item in
                let delta = item.amountUSDT - amountUSDT
                guard delta >= -tolerance, delta <= tolerance else { return false }
                return item.recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(normalizedRecipient) == .orderedSame
            }
    }

    /// Reuse one pending row per recipient+amount until chain history absorbs the confirmed send.
    private func isReusableInFlightTransfer(_ item: PendingTransfer) -> Bool {
        if item.transaction.isProcessing { return true }
        guard case .confirmed = item.transaction.transferStatus else { return false }
        return Date().timeIntervalSince(item.startedAt) < 30 * 60
    }

    /// Drop duplicate Activity rows for the same outbound transfer (retry / double register).
    private func purgeDuplicateActivityTransfers(keepingID: String) {
        guard let keeper = trackedTransfers.first(where: { $0.id == keepingID }) else { return }
        let key = WalletHomeViewModel.activityPendingDedupeKey(keeper.transaction)
        let duplicateIDs = trackedTransfers
            .filter { $0.id != keepingID }
            .filter {
                WalletHomeViewModel.activityPendingDedupeKey($0.transaction) == key
            }
            .map(\.id)
        for id in duplicateIDs {
            removeTracked(id: id)
        }
    }

    /// Removes duplicate Activity rows for the same recipient+amount (keeps newest processing, else newest failed).
    private func dedupeDuplicateActivityTransfers() {
        var grouped: [String: [PendingTransfer]] = [:]

        for item in trackedTransfers {
            switch item.transaction.transferStatus {
            case .processing, .failed:
                let key = WalletHomeViewModel.activityPendingDedupeKey(item.transaction)
                grouped[key, default: []].append(item)
            case .confirmed:
                break
            }
        }

        for (_, items) in grouped where items.count > 1 {
            let keeper = items
                .filter { $0.transaction.isProcessing }
                .max(by: { $0.startedAt < $1.startedAt })
                ?? items.max(by: { $0.startedAt < $1.startedAt })
            guard let keeper else { continue }
            for item in items where item.id != keeper.id {
                removeTracked(id: item.id)
            }
        }
    }

    private func upsertTracked(_ item: PendingTransfer) {
        if let index = trackedTransfers.firstIndex(where: { $0.id == item.id }) {
            trackedTransfers[index] = item
        } else {
            trackedTransfers.insert(item, at: 0)
        }
        dedupeDuplicateActivityTransfers()
    }

    private func persist(_ item: PendingTransfer) {
        MeshPendingSendStore.upsert(item.toRecord())
    }

    private func fetchRecentChain(limit: Int) async -> [WalletTransaction] {
        if MeshWalletCredentials.supportsHDWalletFeatures() {
            guard let history = try? await MeshPrivacyService.fetchActivityHistory(limit: limit) else {
                return []
            }
            return history.map { WalletTransaction(tron: $0) }
        }
        guard let address = try? TronUSDTService.currentAddress(),
              let history = try? await TronUSDTService.fetchTransactions(address: address, limit: limit)
        else { return [] }
        return history.map { WalletTransaction(tron: $0) }
    }

    /// Prefer the spend address history (correct for HD slot 2→main self-transfers).
    private func fetchRecentChainForSpend(fromAddress: String, limit: Int) async -> [WalletTransaction] {
        let spendFrom = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spendFrom.isEmpty,
           let history = try? await TronUSDTService.fetchTransactions(address: spendFrom, limit: limit)
        {
            return history.map { WalletTransaction(tron: $0) }
        }
        return await fetchRecentChain(limit: limit)
    }

    private static func chainMatch(
        for pending: PendingTransfer,
        in chain: [WalletTransaction]
    ) -> WalletTransaction? {
        let recipient = pending.recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let tolerance = Decimal(string: "0.000001") ?? 0
        let notBefore = pending.startedAt.addingTimeInterval(-5)
        let spendFrom = pending.transaction.fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingTxID = pending.transaction.txID.trimmingCharacters(in: .whitespacesAndNewlines)

        func matchesTransfer(_ tx: WalletTransaction) -> Bool {
            // Never treat an on-chain receive as confirmation of an outbound pending send.
            guard tx.kind == .sent else { return false }
            guard !spendFrom.isEmpty,
                  TronAddressCodec.matches(tx.fromAddress, spendFrom)
            else { return false }
            guard TronAddressCodec.matches(tx.toAddress, recipient) else { return false }
            let delta = tx.amountUSDT - pending.amountUSDT
            guard delta >= -tolerance, delta <= tolerance else { return false }
            return tx.timestamp >= notBefore
        }

        if TronUSDTService.isPlausibleTronTransactionID(pendingTxID),
           let byID = chain.first(where: { $0.txID == pendingTxID }),
           matchesTransfer(byID)
        {
            return byID
        }

        // Do not guess from an old transfer when we already have a worker tx id to verify.
        if TronUSDTService.isPlausibleTronTransactionID(pendingTxID) {
            return nil
        }

        guard !spendFrom.isEmpty else { return nil }
        return chain.first(where: matchesTransfer)
    }

    private func sendModel(for item: PendingTransfer) -> SendFlowViewModel {
        if let retainedModel, activeSendID == item.id {
            return retainedModel
        }
        return SendFlowViewModel(replaying: item)
    }

    private func waitForDirectSendMainCompletion(obligationId: String, timeout: TimeInterval = 180) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            guard let status = await MeshSendFeeObligationService.fetchSendStatus(obligationId: obligationId) else {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            if let mainTxID = status.mainTxID, !mainTxID.isEmpty {
                return true
            }
            switch status.status {
            case "send_confirmed_fee_pending", "settled":
                return true
            case "failed":
                return false
            default:
                break
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return false
    }

    private func collectDirectWorkerFeeIfNeeded() async {
        guard let item = current, !item.isPrivateSendMode else { return }
        if await collectDirectWorkerFee(for: item) {
            markNetworkFeeCollected()
        }
    }

    private func collectDirectWorkerFee(for item: PendingTransfer) async -> Bool {
        guard !item.isPrivateSendMode else { return false }
        guard !item.networkFeeCollected else { return true }
        guard item.workerQueued || item.handoffRegistered else { return false }
        if await hasFeeTransferOnChain(for: item) {
            return true
        }

        _ = await waitForDirectSendMainCompletion(obligationId: item.id)

        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if await hasFeeTransferOnChain(for: item) {
                return true
            }
            if await MeshSendFeeObligationService.settleQueuedSendFee(obligationId: item.id) {
                return true
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
        return false
    }

    private func hasFeeTransferOnChain(for item: PendingTransfer) async -> Bool {
        if let status = await MeshSendFeeObligationService.fetchSendStatus(obligationId: item.id),
           let feeTxID = status.feeTxID,
           !feeTxID.isEmpty
        {
            return true
        }

        guard let treasury = MeshSendFees.treasuryAddress else { return false }
        let expectedFee = MeshSendFees.networkFee(
            isPrivateSend: item.isPrivateSendMode,
            mode: item.sendPrivacyMode
        )
        guard expectedFee > 0 else { return true }

        let address = item.transaction.fromAddress.isEmpty
            ? ((try? TronUSDTService.currentAddress()) ?? "")
            : item.transaction.fromAddress
        guard !address.isEmpty else { return false }

        let tolerance = Decimal(string: "0.000001") ?? 0
        let notBefore = item.startedAt.addingTimeInterval(-180)

        if let treasuryHistory = try? await TronAPIService.fetchUSDTTransactions(
            address: treasury,
            limit: 80
        ) {
            if treasuryHistory.contains(where: { tx in
                guard tx.direction == .incoming else { return false }
                guard tx.timestamp >= notBefore else { return false }
                guard TronAddressCodec.matches(tx.fromAddress, address) else { return false }
                let delta = tx.amount - expectedFee
                return delta >= -tolerance && delta <= tolerance
            }) {
                return true
            }
        }

        guard let history = try? await TronAPIService.fetchUSDTTransactions(address: address, limit: 120) else {
            return false
        }

        return history.contains { tx in
            guard tx.direction == .outgoing else { return false }
            guard TronAddressCodec.matches(tx.toAddress, treasury) else { return false }
            guard tx.timestamp >= notBefore else { return false }
            let delta = tx.amount - expectedFee
            return delta >= -tolerance && delta <= tolerance
        }
    }
}
