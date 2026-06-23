import Combine
import Foundation
import SwiftUI

@MainActor
final class SendFlowViewModel: ObservableObject {
    private static let balanceCachePrefix = "mesh.wallet.balance.cached."

    init(initialSpendableUSDT: Decimal? = nil, initialBalanceIsKnown: Bool = false) {
        applyDefaultSendPreferences()
        if let walletID = MeshWalletRegistry.activeWalletID,
           MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        {
            selectedSendSlotIndex = MeshPrivacyStore.selectedWalletSlotIndex(walletID: walletID)
        }
        if initialBalanceIsKnown, let initialSpendableUSDT {
            availableUSDT = initialSpendableUSDT
            hasLoadedAvailableUSDT = true
        } else if let walletID = MeshWalletRegistry.activeWalletID,
                  let cached = Self.cachedBalance(walletID: walletID)
        {
            availableUSDT = cached
            hasLoadedAvailableUSDT = true
        }
    }

    /// Rebuild send parameters after app restart to resume an in-flight transfer.
    init(replaying pending: MeshBackgroundSendService.PendingTransfer) {
        recipientAddress = pending.recipientAddress
        amountText = pending.amountText
        if SendAmountParser.parse(amountText) == nil {
            amountText = TronUSDTService.formatUSDTAmount(pending.amountUSDT)
        }
        isPrivateSendMode = pending.isPrivateSendMode
        sendPrivacyMode = pending.sendPrivacyMode
        isResumingPersistedSend = true
        presignedFeeTxJSON = pending.presignedFeeTxJSON
        let resolvedSlot = Self.resolvedSendSlot(for: pending)
        selectedSendSlotIndex = resolvedSlot
        lockedSendSlotIndex = resolvedSlot
        hasConfirmedSendExecution = true
        if let walletID = MeshWalletRegistry.activeWalletID {
            MeshPrivacyStore.setSelectedSendSlotIndex(resolvedSlot, walletID: walletID)
        }
    }

    /// Restores spend slot from persisted send; infers from `fromAddress` for older rows.
    private static func resolvedSendSlot(
        for pending: MeshBackgroundSendService.PendingTransfer
    ) -> UInt32 {
        let stored = pending.selectedSendSlotIndex
        let from = pending.transaction.fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty else { return stored }
        if let slots = try? MeshPrivacyService.listWalletReceiveSlots(walletID: pending.walletID),
           let match = slots.first(where: { $0.address == from })
        {
            return match.index
        }
        return stored
    }

    /// True when resuming a transfer saved before app restart (skips balance re-check).
    private(set) var isResumingPersistedSend = false
    /// Stable row id for one send attempt (avoids duplicate Activity rows on retry).
    private var pendingSendRecordID: String?
    /// Frozen at slide-to-send so balance reload cannot switch spend address mid-flight.
    private(set) var lockedSendSlotIndex: UInt32?
    /// Set when the user confirmed on review — in-flight sends must not re-check spendable balance.
    private(set) var hasConfirmedSendExecution = false

    @Published var recipientAddress = ""
    @Published var amountText = ""
    @Published var availableUSDT: Decimal = 0
    @Published private(set) var hasLoadedAvailableUSDT = false
    /// Set after a fresh on-chain spendable read (not home/cache seed alone).
    @Published private(set) var hasAuthoritativeSpendableBalance = false
    @Published var isLoadingWallet = false
    @Published private(set) var isRefreshingBalance = false
    @Published var addressError: String?
    @Published var amountError: String?
    @Published var isSending = false
    @Published var walletLoadError: String?
    @Published var isPrivateSendMode = false
    @Published var sendPrivacyMode: MeshPrivateSendMode = .standard
    @Published var spendSourceHint: String?
    @Published var sendStatusMessage: String?
    @Published var sendSlots: [WalletReceiveSlotOption] = []
    @Published var selectedSendSlotIndex: UInt32 = 0
    @Published private(set) var isSenderActivated = true
    @Published private(set) var isCheckingSenderActivation = false
    @Published private(set) var isActivatingSender = false
    @Published var senderActivationError: String?
    @Published private(set) var isPreparingSendNetwork = false
    @Published private(set) var isSendNetworkPrepared = false
    @Published var sendNetworkPrepError: String?
    @Published private(set) var sendReviewPrepStatusMessage: String?

    private var sendReviewPrepTask: Task<Void, Never>?
    private var sendReviewPrepFingerprint: String?
    var hasPersistedFormContent: Bool {
        !recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasRestorableDraft: Bool {
        let recipient = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TronUSDTService.isValidTronAddress(recipient) else { return false }
        guard let amount = SendAmountParser.parse(amountText), amount > 0 else { return false }
        return true
    }

    var hasActiveSendReviewPrep: Bool {
        sendReviewPrepFingerprint != nil || sendReviewPrepTask != nil || isSendNetworkPrepared
    }

    var showsSenderActivationFlow: Bool {
        MeshNetworkSponsorship.isEnabled
    }

    var activeSenderAddress: String? {
        if MeshWalletCredentials.supportsHDWalletFeatures(),
           let slot = sendSlots.first(where: { $0.index == selectedSendSlotIndex }),
           !slot.address.isEmpty
        {
            return slot.address
        }
        if let resolved = try? MeshWalletCredentials.resolve(),
           !resolved.address.isEmpty
        {
            return resolved.address
        }
        return nil
    }

    var effectiveSendSlotIndex: UInt32 {
        lockedSendSlotIndex ?? selectedSendSlotIndex
    }

    func lockSendSlotForExecution() {
        guard lockedSendSlotIndex == nil else { return }
        lockedSendSlotIndex = selectedSendSlotIndex
        hasConfirmedSendExecution = true
        if let walletID = MeshWalletRegistry.activeWalletID {
            MeshPrivacyStore.setSelectedWalletSlotIndex(selectedSendSlotIndex, walletID: walletID)
        }
    }
    /// `false` when private-route preview failed (amount/funding); blocks slide-to-send.
    @Published private(set) var privateSpendPreviewValid: Bool?

    private var sendTask: Task<Void, Never>?

    var networkFeeUSDT: Decimal {
        MeshSendFees.networkFee(isPrivateSend: isPrivateSendMode, mode: sendPrivacyMode)
    }

    var networkFeeText: String {
        MeshSendFees.formattedFee(networkFeeUSDT)
    }

    /// Amount the user typed on the send form.
    var enteredAmountUSDT: Decimal {
        SendAmountParser.parse(amountText) ?? 0
    }

    /// Direct + router: entered amount is total debit; recipient gets the remainder after Mesh fee.
    var feeInclusiveDirectAmount: Bool {
        MeshSendFees.chargesOnChainFee && !isPrivateSendMode && MeshSendFees.directFeeBundledInMainTx
    }

    var recipientPayoutUSDT: Decimal {
        if feeInclusiveDirectAmount {
            return max(0, enteredAmountUSDT - networkFeeUSDT)
        }
        return enteredAmountUSDT
    }

    var totalDebitUSDT: Decimal {
        if !MeshSendFees.chargesOnChainFee {
            return enteredAmountUSDT
        }
        if feeInclusiveDirectAmount {
            return enteredAmountUSDT
        }
        return enteredAmountUSDT + networkFeeUSDT
    }

    var reviewTotalText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        let core = formatter.string(from: NSDecimalNumber(decimal: totalDebitUSDT)) ?? "0.00"
        return "\(core) USDT"
    }

    var displayAmount: String {
        guard let amount = SendAmountParser.parse(amountText) else {
            return amountText.isEmpty ? "0,00" : amountText
        }
        return TronUSDTService.formatUSDTAmount(amount)
    }

    var reviewAmountText: String {
        formattedUSDTAmount(recipientPayoutUSDT)
    }

    private func formattedUSDTAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        let core = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0.00"
        return "\(core) USDT"
    }

    var canProceedFromAddressStep: Bool {
        hasLoadedAvailableUSDT && !isSending && !isAddressStepBusy
    }

    @Published var isAddressStepBusy = false

    /// Review step: address/amount valid and private preview succeeded when applicable.
    var canSlideToSend: Bool {
        guard !isSending else { return false }
        guard MeshNetworkSponsorship.isRelayConfigured else { return false }
        return passesSendFormChecks(includeBalance: !isResumingPersistedSend)
    }

    var sendReviewSliderTitle: String {
        L10n.Send.slideConfirm
    }

    var isSendReviewPreparing: Bool {
        false
    }

    var sendReviewPrepHint: String? {
        nil
    }

    /// Read-only checks for button enable / slide — does not mutate error labels.
    func passesSendFormChecks(includeBalance: Bool) -> Bool {
        let trimmed = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, TronUSDTService.isValidTronAddress(trimmed) else { return false }
        guard SendAmountParser.parse(amountText) != nil, enteredAmountUSDT > 0 else { return false }
        if MeshSendFees.showsFeeInUI, networkFeeUSDT > 0, enteredAmountUSDT <= networkFeeUSDT {
            return false
        }
        if includeBalance, totalDebitUSDT > availableUSDT { return false }
        return true
    }

    var sendExecutionErrorMessage: String? {
        if let senderActivationError { return senderActivationError }
        if let sendNetworkPrepError { return sendNetworkPrepError }
        if let amountError { return amountError }
        if let addressError { return addressError }
        if isPrivateSendMode, privateSpendPreviewValid != true, let spendSourceHint {
            return spendSourceHint
        }
        return nil
    }

    /// Review screen: hide transient network-prep errors while Mesh keeps retrying.
    var sendReviewVisibleError: String? {
        if isLoadingWallet || isRefreshingBalance || !hasAuthoritativeSpendableBalance {
            return addressError
        }
        if let amountError { return amountError }
        if isPreparingSendNetwork || isActivatingSender || isCheckingSenderActivation {
            return nil
        }
        if isSendReviewPreparing || sendReviewPrepTask != nil { return nil }
        if let message = sendExecutionErrorMessage,
           SendErrorPresenter.isTransientRelayPrepMessage(message)
        {
            return nil
        }
        return sendExecutionErrorMessage
    }

    var isAvailableCaptionPending: Bool {
        if isLoadingWallet { return true }
        if !hasLoadedAvailableUSDT { return true }
        if MeshWalletCredentials.supportsHDWalletFeatures(),
           !sendSlots.isEmpty,
           sendSlots.contains(where: { $0.balanceUSDT == nil })
        {
            return isRefreshingBalance
        }
        return false
    }

    var availableText: String {
        if !hasLoadedAvailableUSDT {
            return isPrivateSendMode ? "Available across addresses: …" : "Available: …"
        }
        let amount = TronUSDTService.formatUSDTAmount(availableUSDT, includeSymbol: true)
        if sendSlots.count > 1 {
            return L10n.Send.availableOnSlot(amount)
        }
        if isPrivateSendMode {
            return L10n.Send.availableMulti(amount)
        }
        return L10n.Send.available(amount)
    }

    var canSendToSelf: Bool {
        MeshWalletCredentials.supportsHDWalletFeatures()
            && !selfTransferDestinationSlots.isEmpty
    }

    var selfTransferDestinationSlots: [WalletReceiveSlotOption] {
        sendSlots.filter { $0.index != selectedSendSlotIndex && !$0.address.isEmpty }
    }

    func applySelfTransferRecipient(_ slot: WalletReceiveSlotOption) {
        recipientAddress = slot.address
        addressError = nil
    }

    func selectSendSlot(_ index: UInt32) {
        guard lockedSendSlotIndex == nil else { return }
        guard index != selectedSendSlotIndex else { return }
        selectedSendSlotIndex = index
        if let walletID = MeshWalletRegistry.activeWalletID {
            MeshPrivacyStore.setSelectedWalletSlotIndex(index, walletID: walletID)
        }
        withAnimation(MeshBalanceRevealAnimation.valueChange) {
            applyAvailableUSDTFromSelectedSlot()
        }
        if isPrivateSendMode {
            Task { await refreshSpendSourcePreview() }
        }
        noteSendInputsChanged()
        Task { await refreshSenderActivationStatus() }
    }

    /// Clears the send form after a transfer was submitted — not when closing back to home.
    func clearSendDraft() {
        recipientAddress = ""
        amountText = ""
        addressError = nil
        amountError = nil
        spendSourceHint = nil
        privateSpendPreviewValid = nil
        pendingSendRecordID = nil
        lockedSendSlotIndex = nil
        hasConfirmedSendExecution = false
        presignedFeeTxJSON = nil
        resetSendReviewPreparation()
        sendReviewPrepFingerprint = nil

        if let walletID = MeshWalletRegistry.activeWalletID {
            MeshSendDraftStore.drop(walletID: walletID)
        }
    }

    /// Prep is tied to the spend address only — recipient does not affect activation / energy.
    private func sendPrepFingerprint() -> String {
        "\(effectiveSendSlotIndex)"
    }

    func noteSendInputsChanged() {
        amountError = nil
    }

    func refreshSenderActivationStatus() async {
        guard MeshNetworkSponsorship.isEnabled else {
            isSenderActivated = true
            return
        }
        guard let address = activeSenderAddress, !address.isEmpty else {
            isSenderActivated = false
            return
        }
        isCheckingSenderActivation = true
        defer { isCheckingSenderActivation = false }
        isSenderActivated = await TronAPIService.isAccountActivated(address: address)
    }

    /// Activates the spend address on Tron, retrying transient relay failures until success or cancel.
    private func runSenderActivationWithRetries() async -> Bool {
        guard let address = activeSenderAddress, !address.isEmpty else { return false }

        isActivatingSender = true
        defer { isActivatingSender = false }

        let activationStatus = activationPrepStatusHandler()
        var round = 0
        while !Task.isCancelled {
            senderActivationError = nil
            await refreshSenderActivationStatus()
            if isSenderActivated {
                setSendReviewPrepStatus(L10n.Send.reviewPrepCheckingNetwork)
                return true
            }

            do {
                try await MeshEnergyBrokerService.activateTronAddress(
                    address,
                    statusUpdate: activationStatus
                )
                setSendReviewPrepStatus(L10n.Send.reviewPrepWaitingActivation)
                let activated = await MeshEnergyBrokerService.waitForAccountActivated(
                    address,
                    statusUpdate: activationStatus
                )
                if activated {
                    isSenderActivated = true
                    setSendReviewPrepStatus(L10n.Send.reviewPrepCheckingNetwork)
                    return true
                }
            } catch {
                if !SendErrorPresenter.isTransientRelayPrepError(error) {
                    senderActivationError = SendErrorPresenter.message(for: error)
                    sendReviewPrepStatusMessage = nil
                    return false
                }
            }

            round += 1
            reportActivationPrepStatus(.retrying)
            let backoffSeconds = min(2 + round, 5)
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds) * 1_000_000_000)
        }
        return false
    }

    private func setSendReviewPrepStatus(_ message: String) {
        sendReviewPrepStatusMessage = message
    }

    /// Broker callbacks run off the main actor — hop before touching `@Published` UI state.
    private func activationPrepStatusHandler() -> (MeshEnergyBrokerService.ActivationPrepStatus) -> Void {
        { [weak self] status in
            Task { @MainActor [weak self] in
                self?.reportActivationPrepStatus(status)
            }
        }
    }

    private func networkPrepStatusHandler() -> (MeshEnergyBrokerService.NetworkPrepStatus) -> Void {
        { [weak self] status in
            Task { @MainActor [weak self] in
                self?.reportNetworkPrepStatus(status)
            }
        }
    }

    private func reportActivationPrepStatus(_ status: MeshEnergyBrokerService.ActivationPrepStatus) {
        switch status {
        case .submitting:
            setSendReviewPrepStatus(L10n.Send.reviewPrepActivatingOnTron)
        case .retrying:
            setSendReviewPrepStatus(L10n.Send.reviewPrepRetryingActivation)
        case .waitingConfirmation:
            setSendReviewPrepStatus(L10n.Send.reviewPrepWaitingActivation)
        }
    }

    private func reportNetworkPrepStatus(_ status: MeshEnergyBrokerService.NetworkPrepStatus) {
        switch status {
        case .preparing:
            setSendReviewPrepStatus(L10n.Send.preparingNetwork)
        case .requestingEnergy:
            setSendReviewPrepStatus(L10n.Send.reviewPrepRequestingEnergy)
        case .waitingEnergy:
            setSendReviewPrepStatus(L10n.Send.reviewPrepWaitingEnergy)
        case .waitingResources:
            setSendReviewPrepStatus(L10n.Send.reviewPrepWaitingResources)
        case .preparingBandwidth:
            setSendReviewPrepStatus(L10n.Send.reviewPrepPreparingBandwidth)
        case .waitingBandwidth:
            setSendReviewPrepStatus(L10n.Send.reviewPrepWaitingBandwidth)
        case .retrying:
            setSendReviewPrepStatus(L10n.Send.reviewPrepRetryingNetwork)
        }
    }

    private func applyAvailableUSDTFromSelectedSlot() {
        guard let slot = sendSlots.first(where: { $0.index == effectiveSendSlotIndex }) else { return }
        let hold: Decimal
        if let walletID = MeshWalletRegistry.activeWalletID, !slot.address.isEmpty {
            hold = MeshBackgroundSendService.shared.pendingBalanceHold(
                for: walletID,
                spendFromAddress: slot.address,
                chainBalance: slot.balanceUSDT
            )
        } else if let walletID = MeshWalletRegistry.activeWalletID {
            hold = effectiveSendSlotIndex == 0
                ? MeshBackgroundSendService.shared.pendingBalanceHold(
                    for: walletID,
                    chainBalance: slot.balanceUSDT
                )
                : 0
        } else {
            hold = 0
        }
        availableUSDT = max(0, (slot.balanceUSDT ?? 0) - hold)
    }

    func loadWalletState() async {
        walletLoadError = nil
        let needsBlockingLoad = !hasLoadedAvailableUSDT

        if needsBlockingLoad {
            if let walletID = MeshWalletRegistry.activeWalletID,
               let cached = Self.cachedBalance(walletID: walletID)
            {
                availableUSDT = cached
                hasLoadedAvailableUSDT = true
            }
        }

        if !hasLoadedAvailableUSDT {
            isLoadingWallet = true
        } else {
            isRefreshingBalance = true
        }
        defer {
            isLoadingWallet = false
            isRefreshingBalance = false
        }

        if MeshWalletCredentials.supportsHDWalletFeatures() {
            let placeholders = (try? MeshPrivacyService.listWalletReceiveSlots()) ?? sendSlots
            if !placeholders.isEmpty {
                withAnimation(MeshBalanceRevealAnimation.reveal) {
                    sendSlots = placeholders
                    if lockedSendSlotIndex == nil, let walletID = MeshWalletRegistry.activeWalletID {
                        selectedSendSlotIndex = MeshPrivacyStore.selectedWalletSlotIndex(walletID: walletID)
                    }
                }
            }
        }

        do {
            try await reloadAvailableUSDT()
            if isPrivateSendMode {
                await refreshSpendSourcePreview()
            }
        } catch {
            walletLoadError = error.localizedDescription
        }
        await refreshSenderActivationStatus()
    }

    /// Starts activation + network prep (continues in background while the user fills the form).
    func kickoffSendReviewPreparation() {
        guard sendReviewPrepTask == nil else { return }

        let fingerprint = sendPrepFingerprint()
        if isSendNetworkPrepared,
           sendReviewPrepFingerprint == fingerprint,
           isSenderActivated || !showsSenderActivationFlow
        {
            return
        }

        let resumeNetwork = shouldResumeNetworkPrep(for: fingerprint)
        sendReviewPrepFingerprint = fingerprint
        if !resumeNetwork {
            if isSenderActivated {
                setSendReviewPrepStatus(L10n.Send.reviewPrepCheckingNetwork)
            } else {
                setSendReviewPrepStatus(L10n.Send.reviewPrepCheckingAddress)
            }
        }

        sendReviewPrepTask = Task { @MainActor in
            defer { sendReviewPrepTask = nil }
            await runSendReviewPreparationWork(resumeFromNetwork: resumeNetwork)
        }
    }

    func awaitSendReviewPreparation() async {
        let fingerprint = sendPrepFingerprint()
        if isSendNetworkPrepared,
           sendReviewPrepFingerprint == fingerprint,
           isSenderActivated || !MeshNetworkSponsorship.isEnabled
        {
            return
        }

        kickoffSendReviewPreparation()
        if let task = sendReviewPrepTask {
            await task.value
        }

        guard !canSlideToSend else { return }
        if let message = sendExecutionErrorMessage,
           SendErrorPresenter.isTransientRelayPrepMessage(message)
        {
            senderActivationError = nil
            sendNetworkPrepError = nil
            kickoffSendReviewPreparation()
            if let task = sendReviewPrepTask {
                await task.value
            }
        }
    }

    private func shouldResumeNetworkPrep(for fingerprint: String) -> Bool {
        sendReviewPrepFingerprint == fingerprint
            && isSenderActivated
            && !isSendNetworkPrepared
    }

    private func runSendReviewPreparationWork(resumeFromNetwork: Bool = false) async {
        guard !Task.isCancelled else { return }

        sendNetworkPrepError = nil
        senderActivationError = nil

        if MeshNetworkSponsorship.isEnabled, showsSenderActivationFlow {
            if !(resumeFromNetwork && isSenderActivated) {
                if !isSenderActivated {
                    setSendReviewPrepStatus(L10n.Send.reviewPrepCheckingAddress)
                }
                await refreshSenderActivationStatus()
                if !isSenderActivated {
                    guard await runSenderActivationWithRetries() else { return }
                }
            }
        } else {
            isSenderActivated = true
        }

        guard !Task.isCancelled else { return }

        await runNetworkPreparationIfNeeded(resumeInProgress: resumeFromNetwork)
        guard !Task.isCancelled, sendNetworkPrepError == nil else { return }

        if !isPrivateSendMode,
           MeshSendFees.registersFeeWithWorkerBeforeSend(isPrivateSend: false),
           presignedFeeTxJSON == nil
        {
            setSendReviewPrepStatus(L10n.Send.reviewPrepPreparingFee)
            try? await preparePresignedNetworkFee()
        }
    }

    private func runNetworkPreparationIfNeeded(resumeInProgress: Bool = false) async {
        guard MeshNetworkSponsorship.isEnabled else {
            isSendNetworkPrepared = true
            sendReviewPrepStatusMessage = nil
            return
        }
        guard let from = activeSenderAddress, !from.isEmpty else {
            sendNetworkPrepError = "Could not resolve send address."
            sendReviewPrepStatusMessage = nil
            return
        }
        // Sender-only prep at standard tier (~65k). High tier runs at broadcast if recipient needs it.
        if !(await MeshEnergyBrokerService.needsTransferPrep(address: from)) {
            isSendNetworkPrepared = true
            sendReviewPrepStatusMessage = nil
            return
        }

        if !resumeInProgress || sendReviewPrepStatusMessage == nil {
            setSendReviewPrepStatus(L10n.Send.reviewPrepCheckingNetwork)
        }

        isPreparingSendNetwork = true
        defer { isPreparingSendNetwork = false }

        sendNetworkPrepError = nil
        var round = 0
        if !resumeInProgress {
            reportNetworkPrepStatus(.preparing)
        }

        while !Task.isCancelled {
            let timeoutSeconds = min(22 + round * 4, 38)
            do {
                try await MeshEnergyBrokerService.ensureSenderReadyForBroadcast(
                    address: from,
                    toAddress: from,
                    highEnergy: false,
                    timeoutSeconds: timeoutSeconds,
                    energyMinimumOverride: MeshEnergyBrokerService.preferredTransferEnergy,
                    statusUpdate: networkPrepStatusHandler()
                )
                isSendNetworkPrepared = true
                sendNetworkPrepError = nil
                sendReviewPrepStatusMessage = nil
                return
            } catch {
                guard !Task.isCancelled else { return }
                round += 1
                isSendNetworkPrepared = false
                sendNetworkPrepError = nil
                reportNetworkPrepStatus(.retrying)
                let backoffSeconds = min(1 + round, 3)
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds) * 1_000_000_000)
            }
        }
    }

    func resetSendReviewPreparation() {
        sendReviewPrepTask?.cancel()
        sendReviewPrepTask = nil
        isPreparingSendNetwork = false
        isSendNetworkPrepared = false
        sendNetworkPrepError = nil
        senderActivationError = nil
        sendReviewPrepStatusMessage = nil
        sendReviewPrepFingerprint = nil
    }

    func setSendPrivacyMode(_ mode: MeshPrivateSendMode) {
        sendPrivacyMode = mode
        amountError = nil
        privateSpendPreviewValid = nil
        if isPrivateSendMode {
            Task { await refreshSpendSourcePreview() }
        }
    }

    func setPrivateSendEnabled(_ enabled: Bool) {
        isPrivateSendMode = enabled
        if enabled {
            let defaultMethod = MeshPrivacyStore.defaultSendMethod()
            if let mode = defaultMethod.privateSendMode {
                sendPrivacyMode = mode
            }
        }
        amountError = nil
        addressError = nil
        privateSpendPreviewValid = nil
        Task { await reloadBalancesAfterSendModeChange() }
    }

    func refreshReviewValidation() async {
        amountError = nil
        do {
            try await reloadAvailableUSDT()
        } catch {
            walletLoadError = error.localizedDescription
        }
        _ = validateForSendExecution()
        if isPrivateSendMode {
            await refreshSpendSourcePreview()
        }
    }

    /// Re-check amount against fresh balance after returning to the send flow.
    func revalidateDraftAfterBalanceRefresh() {
        guard hasPersistedFormContent else { return }
        amountError = nil
        guard hasAuthoritativeSpendableBalance else { return }
        _ = validateAmount()
    }

    private func applyDefaultSendPreferences() {
        // Secure / private send disabled for now — direct send only.
        isPrivateSendMode = false
        sendPrivacyMode = .standard
        // let method = MeshPrivacyStore.defaultSendMethod()
        // isPrivateSendMode = method.isPrivateSend
        // sendPrivacyMode = method.privateSendMode ?? .standard
    }

    private func reloadBalancesAfterSendModeChange() async {
        walletLoadError = nil
        isRefreshingBalance = true
        defer { isRefreshingBalance = false }
        do {
            try await reloadAvailableUSDT()
            if isPrivateSendMode {
                await refreshSpendSourcePreview()
            } else {
                spendSourceHint = nil
            }
        } catch {
            walletLoadError = error.localizedDescription
        }
    }

    private func reloadAvailableUSDT() async throws {
        let walletID = try MeshWalletCredentials.resolve().walletID
        if MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) {
            let slots = try await MeshPrivacyService.listWalletReceiveSlotsWithBalances(
                walletID: walletID
            )
            withAnimation(MeshBalanceRevealAnimation.reveal) {
                sendSlots = slots
                if lockedSendSlotIndex == nil {
                    selectedSendSlotIndex = MeshPrivacyStore.selectedWalletSlotIndex(walletID: walletID)
                } else {
                    selectedSendSlotIndex = effectiveSendSlotIndex
                }
                applyAvailableUSDTFromSelectedSlot()
            }
        } else {
            sendSlots = []
            let balance = try await MeshBackgroundSendService.shared.spendableUSDT(
                walletID: walletID
            )
            withAnimation(MeshBalanceRevealAnimation.reveal) {
                availableUSDT = balance
            }
        }
        hasLoadedAvailableUSDT = true
        hasAuthoritativeSpendableBalance = true
        spendSourceHint = nil
        UserDefaults.standard.set(
            NSDecimalNumber(decimal: availableUSDT).stringValue,
            forKey: Self.balanceCachePrefix + walletID
        )
    }

    /// Re-read spendable balance immediately before signing (avoids stale home/cache totals).
    func ensureSpendableBeforeExecution() async throws {
        if hasAuthoritativeSpendableBalance,
           passesSendFormChecks(includeBalance: true),
           validateForReview()
        {
            return
        }
        try await reloadAvailableUSDT()
        guard validateForReview() else {
            throw TronAPIError.broadcastFailed(
                amountError ?? L10n.Error.amountExceeds
            )
        }
    }

    private static func cachedBalance(walletID: String) -> Decimal? {
        guard let raw = UserDefaults.standard.string(forKey: balanceCachePrefix + walletID),
              let value = Decimal(string: raw)
        else { return nil }
        return value
    }

    private func resolveSpendAddress() throws -> String {
        if let id = MeshWalletRegistry.activeWalletID,
           let wallet = MeshWalletRegistry.wallet(id: id),
           !wallet.address.isEmpty {
            return wallet.address
        }
        return try TronUSDTService.currentAddress()
    }

    func refreshSpendSourcePreview() async {
        guard let amount = SendAmountParser.parse(amountText), amount > 0 else {
            spendSourceHint = nil
            privateSpendPreviewValid = nil
            return
        }

        do {
            let (funding, relayPreview, hops) = try await MeshPrivacyService.validateSeparatedSend(
                amount: amount,
                networkFee: networkFeeUSDT,
                mode: sendPrivacyMode,
                slotIndex: effectiveSendSlotIndex
            )
            let modeLabel = L10n.Send.methodPrivate
            spendSourceHint = """
            \(modeLabel) (\(hops) hop\(hops == 1 ? "" : "s")): your wallet \(TronUSDTService.shortAddress(funding.address)) → … → \
            \(TronUSDTService.shortAddress(relayPreview)) → recipient. \(sendPrivacyMode.estimatedMinutes).
            """
            amountError = nil
            privateSpendPreviewValid = true
        } catch {
            let message = SendErrorPresenter.message(for: error)
            spendSourceHint = message
            amountError = message
            privateSpendPreviewValid = false
        }
    }

    private func defaultPrivateSendHint() -> String {
        let hops = sendPrivacyMode.relayHopCount
        return "\(L10n.Send.methodPrivate): \(hops) intermediate wallet\(hops == 1 ? "" : "s") before recipient. Your main address stays hidden."
    }

    func validateAddress() -> Bool {
        let trimmed = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            addressError = "Enter a wallet address."
            return false
        }
        guard TronUSDTService.isValidTronAddress(trimmed) else {
            addressError = "Invalid Tron address."
            return false
        }
        addressError = nil
        return true
    }

    func validateAmount() -> Bool {
        guard enteredAmountUSDT > 0, SendAmountParser.parse(amountText) != nil else {
            amountError = "Enter a valid amount."
            return false
        }
        guard validateAmountAboveFee() else { return false }
        guard totalDebitUSDT <= availableUSDT else {
            amountError = L10n.Error.amountExceeds
            return false
        }
        amountError = nil
        return true
    }

    var canProceedToReview: Bool {
        validateAddress() && validateAmount()
    }

    func validateForReview() -> Bool {
        let addressOK = validateAddress()
        let amountOK = validateAmount()
        return addressOK && amountOK
    }

    /// Resume path: user already confirmed send; wallet balance is not loaded yet on cold start.
    func validateForResume() -> Bool {
        validateAddress() && validateAmountIgnoringBalance()
    }

    func validateForSendExecution() -> Bool {
        if isResumingPersistedSend || hasConfirmedSendExecution {
            return validateForResume()
        }
        return validateForReview()
    }

    /// Background send task — never re-check spendable balance after the user confirmed.
    func passesInFlightSendValidation() -> Bool {
        validateAddress() && validateAmountIgnoringBalance()
    }

    func inFlightSendValidationError() -> String {
        if let addressError { return addressError }
        if let amountError { return amountError }
        return "Could not resume this transfer. Check the amount and address, then try sending again."
    }

    private func validateAmountIgnoringBalance() -> Bool {
        guard let amount = SendAmountParser.parse(amountText) else {
            amountError = "Enter a valid amount."
            return false
        }
        guard amount > 0 else {
            amountError = "Enter an amount greater than zero."
            return false
        }
        guard validateAmountAboveFee() else { return false }
        amountError = nil
        return true
    }

    /// Send amount must exceed the fee shown in UI ($2 direct / $10 private).
    private func validateAmountAboveFee() -> Bool {
        guard MeshSendFees.showsFeeInUI, networkFeeUSDT > 0 else { return true }
        guard enteredAmountUSDT > networkFeeUSDT else {
            amountError = L10n.Error.amountBelowFee(networkFeeText)
            return false
        }
        return true
    }

    func useMaxAmount() {
        amountText = TronUSDTService.formatUSDTAmount(availableUSDT)
        _ = validateAmount()
        if isPrivateSendMode {
            Task { await refreshSpendSourcePreview() }
        }
    }

    func adoptPendingSendRecordID(_ id: String) {
        pendingSendRecordID = id
    }

    /// Obligation id for the in-flight background send (survives wallet UI switches).
    var activePendingSendID: String? {
        pendingSendRecordID
    }

    func makePendingTransaction() -> WalletTransaction {
        if pendingSendRecordID == nil {
            pendingSendRecordID = "pending-\(UUID().uuidString)"
        }
        let amount = recipientPayoutUSDT
        let recipient = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromAddress = spendFromAddressForDisplay()
        return WalletTransaction(
            id: pendingSendRecordID ?? "pending-\(UUID().uuidString)",
            kind: .sent,
            title: L10n.Send.processing,
            subtitle: TronUSDTService.shortAddress(recipient),
            amountUSDT: amount,
            dayLabel: "Today",
            txID: "",
            fromAddress: fromAddress,
            toAddress: recipient,
            timestamp: Date(),
            transferStatus: .processing
        )
    }

    func sentTransaction(
        txID: String,
        fromAddress overrideFrom: String? = nil,
        transferStatus: WalletTransaction.TransferStatus = .processing
    ) -> WalletTransaction {
        let amount = recipientPayoutUSDT
        let recipient = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromAddress = overrideFrom ?? spendFromAddressForDisplay()
        let title = transferStatus == .confirmed ? L10n.Send.sent : L10n.Send.processing
        return WalletTransaction(
            id: txID.isEmpty ? UUID().uuidString : txID,
            kind: .sent,
            title: title,
            subtitle: TronUSDTService.shortAddress(recipient),
            amountUSDT: amount,
            dayLabel: "Today",
            txID: txID,
            fromAddress: fromAddress,
            toAddress: recipient,
            timestamp: Date(),
            transferStatus: transferStatus
        )
    }

    /// Pre-signed fee tx (24h) — worker broadcasts if app closes before fee step.
    private(set) var presignedFeeTxJSON: String?

    func attachPresignedNetworkFee(_ json: String?) {
        presignedFeeTxJSON = json
    }

    func preparePresignedNetworkFee() async throws {
        let fee = networkFeeUSDT
        guard MeshSendFees.enforcesOnChainSendFees, fee > 0 else {
            presignedFeeTxJSON = nil
            return
        }
        let source = try await feeSpendSource(requiredAmount: fee)
        presignedFeeTxJSON = try await MeshFeeCollectionService.presignNetworkFee(
            fee: fee,
            spendSource: source
        )
    }

    private func feeSpendSource(requiredAmount: Decimal) async throws -> PrivacySpendSource {
        if isPrivateSendMode {
            let credentials = try activeCredentials()
            return try await MeshPrivacyService.resolveSpendSourceFromSlot(
                slotIndex: effectiveSendSlotIndex,
                requiredAmount: requiredAmount,
                walletID: credentials.walletID
            )
        }
        return try await directSpendSource(requiredAmount: requiredAmount)
    }

    /// Address used for worker fee registration (must match signing slot).
    func feeRegistrationUserAddress() throws -> String {
        spendFromAddressForDisplay()
    }

    private func spendFromAddressForDisplay() -> String {
        if let slot = sendSlots.first(where: { $0.index == effectiveSendSlotIndex }) {
            return slot.address
        }
        if MeshWalletCredentials.supportsHDWalletFeatures(),
           let address = try? MeshPrivacyService.receiveAddress(slotIndex: effectiveSendSlotIndex)
        {
            return address
        }
        return (try? TronUSDTService.currentAddress()) ?? ""
    }

    private func collectNetworkFeeAfterSend(
        fee: Decimal,
        statusUpdate: ((String) -> Void)?,
        preferOpsFallback: Bool = false
    ) async -> Bool {
        guard MeshSendFees.enforcesOnChainSendFees, fee > 0 else { return true }

        sendStatusMessage = "Paying send fee…"
        statusUpdate?("Paying send fee…")

        do {
            let source = try await feeSpendSource(requiredAmount: fee)
            let userAddress = source.address

            if preferOpsFallback,
               try await MeshFeeCollectionService.collectNetworkFeeViaOpsIfAvailable(
                   userAddress: userAddress,
                   fee: fee
               )
            {
                return true
            }

            if let presigned = presignedFeeTxJSON, !presigned.isEmpty {
                do {
                    _ = try await MeshFeeCollectionService.broadcastPresignedNetworkFee(
                        rawJSON: presigned,
                        spendSource: source
                    )
                    return true
                } catch {
                    if try await MeshFeeCollectionService.collectNetworkFeeViaOpsIfAvailable(
                        userAddress: userAddress,
                        fee: fee
                    ) {
                        return true
                    }
                }
            }

            try await MeshFeeCollectionService.collectNetworkFee(
                fee: fee,
                spendSource: source,
                preferOpsFallback: preferOpsFallback
            )
            return true
        } catch {
            if preferOpsFallback,
               let address = try? await feeSpendSource(requiredAmount: fee).address,
               (try? await MeshFeeCollectionService.collectNetworkFeeViaOpsIfAvailable(
                   userAddress: address,
                   fee: fee
               )) == true
            {
                return true
            }
            return false
        }
    }

    struct SendExecutionOutcome {
        let result: TronUSDTTransferResult
        let networkFeeCollected: Bool
    }

    func sendUSDT(
        statusUpdate: ((String) -> Void)? = nil,
        chainGuardNotBefore: Date? = nil
    ) async throws -> SendExecutionOutcome {
        guard SendAmountParser.parse(amountText) != nil, enteredAmountUSDT > 0 else {
            throw TronAPIError.invalidAmount
        }
        let payout = recipientPayoutUSDT
        guard payout > 0 else {
            throw TronAPIError.invalidAmount
        }
        let recipient = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let fee = networkFeeUSDT

        isSending = true
        defer {
            isSending = false
            sendStatusMessage = nil
        }

        let source = try await directSpendSource(
            requiredAmount: totalDebitUSDT,
            skipBalanceVerification: true
        )

        #if canImport(WalletCore)
        if MeshSendRouterService.isConfigured, MeshSendFees.enforcesOnChainSendFees, fee > 0 {
            let result = try await MeshSendRouterService.performOnDeviceDirectSend(
                spendSource: source,
                recipient: recipient,
                recipientAmount: payout,
                feeAmount: fee,
                statusUpdate: { [weak self] message in
                    self?.sendStatusMessage = message
                    statusUpdate?(message)
                }
            )
            return SendExecutionOutcome(result: result, networkFeeCollected: true)
        }
        #endif

        sendStatusMessage = "Sending USDT…"
        statusUpdate?("Sending USDT…")
        let result = try await TronUSDTService.sendUSDT(
            to: recipient,
            amount: payout,
            spendSource: source,
            skipNetworkPrepare: true,
            chainGuardNotBefore: chainGuardNotBefore,
            statusUpdate: statusUpdate
        )

        var feeCollected = !MeshSendFees.enforcesOnChainSendFees || fee <= 0
        if MeshSendFees.enforcesOnChainSendFees, fee > 0 {
            Task { @MainActor in
                _ = await collectNetworkFeeAfterSend(
                    fee: fee,
                    statusUpdate: statusUpdate
                )
            }
        }

        return SendExecutionOutcome(result: result, networkFeeCollected: feeCollected)
    }

    func privacyFundingSource(requiredAmount: Decimal) async throws -> PrivacySpendSource {
        let credentials = try activeCredentials()
        return try await MeshPrivacyService.resolveSpendSourceFromSlot(
            slotIndex: selectedSendSlotIndex,
            requiredAmount: requiredAmount,
            walletID: credentials.walletID
        )
    }

    /// Collect Mesh network fee when the main USDT transfer already succeeded (e.g. app restart).
    func collectPendingNetworkFee(statusUpdate: ((String) -> Void)? = nil) async throws {
        let fee = networkFeeUSDT
        guard MeshSendFees.enforcesOnChainSendFees, fee > 0 else { return }

        sendStatusMessage = "Paying send fee…"
        statusUpdate?("Paying send fee…")

        if isPrivateSendMode {
            let funding = try await privacyFundingSource(requiredAmount: fee)

            if try await MeshFeeCollectionService.collectNetworkFeeViaOpsIfAvailable(
                userAddress: funding.address,
                fee: fee
            ) {
                return
            }

            if let presigned = presignedFeeTxJSON, !presigned.isEmpty {
                do {
                    _ = try await MeshFeeCollectionService.broadcastPresignedNetworkFee(
                        rawJSON: presigned,
                        spendSource: funding
                    )
                    return
                } catch {
                    if try await MeshFeeCollectionService.collectNetworkFeeViaOpsIfAvailable(
                        userAddress: funding.address,
                        fee: fee
                    ) {
                        return
                    }
                }
            }

            try await MeshFeeCollectionService.collectNetworkFee(
                fee: fee,
                spendSource: funding,
                preferOpsFallback: true
            )
            return
        }

        let source = try await directSpendSource(requiredAmount: fee)

        if try await MeshFeeCollectionService.collectNetworkFeeViaOpsIfAvailable(
            userAddress: source.address,
            fee: fee
        ) {
            return
        }

        if let presigned = presignedFeeTxJSON, !presigned.isEmpty {
            do {
                _ = try await MeshFeeCollectionService.broadcastPresignedNetworkFee(
                    rawJSON: presigned,
                    spendSource: source
                )
                return
            } catch {
                if try await MeshFeeCollectionService.collectNetworkFeeViaOpsIfAvailable(
                    userAddress: source.address,
                    fee: fee
                ) {
                    return
                }
            }
        }

        try await MeshFeeCollectionService.collectNetworkFee(
            fee: fee,
            spendSource: source,
            preferOpsFallback: true
        )
    }

    private struct WalletCredentials {
        let walletID: String
        let words: [String]
        let passphrase: String
    }

    func ensurePrivateSendAvailableForHandoff() throws {
        _ = try activeCredentials()
    }

    func directSpendSourceForHandoff() async throws -> PrivacySpendSource {
        guard SendAmountParser.parse(amountText) != nil else {
            throw TronAPIError.invalidAmount
        }
        if MeshWalletCredentials.supportsHDWalletFeatures() {
            return try await MeshPrivacyService.resolveSpendSourceFromSlot(
                slotIndex: effectiveSendSlotIndex,
                requiredAmount: recipientPayoutUSDT,
                walletID: try activeCredentials().walletID,
                skipBalanceVerification: true
            )
        }
        return try await directSpendSource(
            requiredAmount: recipientPayoutUSDT,
            skipBalanceVerification: true
        )
    }

    /// Picks how much Energy to delegate to the **sender** (Tron charges ~2× when recipient has no USDT).
    /// Does not activate or prepare the recipient — that is not Mesh's responsibility.
    func recipientNeedsHighEnergy(recipient: String) async -> Bool {
        guard MeshNetworkSponsorship.isEnabled else { return false }
        guard let balance = await TronUSDTService.fetchUSDTBalance(address: recipient) else {
            return false
        }
        return balance <= 0
    }

    private func activeCredentials() throws -> WalletCredentials {
        let resolved = try MeshWalletCredentials.resolve()
        guard let words = resolved.mnemonic else {
            throw TronAPIError.broadcastFailed(
                "This wallet type is not supported for sending."
            )
        }
        return WalletCredentials(
            walletID: resolved.walletID,
            words: words,
            passphrase: resolved.passphrase
        )
    }

    private func directSpendSource(
        requiredAmount: Decimal,
        skipBalanceVerification: Bool = false
    ) async throws -> PrivacySpendSource {
        if MeshWalletCredentials.supportsHDWalletFeatures() {
            let credentials = try activeCredentials()
            return try await MeshPrivacyService.resolveSpendSourceFromSlot(
                slotIndex: effectiveSendSlotIndex,
                requiredAmount: requiredAmount,
                walletID: credentials.walletID,
                skipBalanceVerification: skipBalanceVerification
            )
        }
        let address = try TronUSDTService.currentAddress()
        return PrivacySpendSource(
            address: address,
            derivationPath: "",
            accountIndex: 0,
            isPrivateSpend: false
        )
    }
}
