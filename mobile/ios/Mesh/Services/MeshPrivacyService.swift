import Foundation

struct PrivacyReceiveContext: Equatable {
    let address: String
    let accountIndex: UInt32
    let isPrivateMode: Bool
    let paymentNumber: Int
}

struct WalletReceiveSlotOption: Identifiable, Equatable {
    let index: UInt32
    let address: String
    let title: String
    let derivationPath: String
    var balanceUSDT: Decimal?

    var id: UInt32 { index }

    var formattedBalance: String {
        guard let balanceUSDT else { return "—" }
        return TronUSDTService.formatUSDTAmount(balanceUSDT, includeSymbol: true)
    }
}

struct PrivacySpendSource: Equatable {
    let address: String
    let derivationPath: String
    let accountIndex: UInt32
    let isPrivateSpend: Bool
}

enum MeshPrivacyService {
    static func isPrivateSendEnabled(walletID: String? = MeshWalletRegistry.activeWalletID) -> Bool {
        MeshPrivacyStore.isPrivateSendEnabled(walletID: walletID)
    }

    static func isPrivateModeEnabled(walletID: String? = MeshWalletRegistry.activeWalletID) -> Bool {
        isPrivateSendEnabled(walletID: walletID)
    }

    // MARK: - Receive

    static func listWalletReceiveSlots(
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) throws -> [WalletReceiveSlotOption] {
        if !MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) {
            let resolved = try MeshWalletCredentials.resolve(walletID: walletID)
            let path = resolved.derivationPath.isEmpty
                ? TronWalletService.receiveDerivationPath(accountIndex: 0)
                : resolved.derivationPath
            return [
                WalletReceiveSlotOption(
                    index: 0,
                    address: resolved.address,
                    title: L10n.Receive.mainAddress,
                    derivationPath: path,
                    balanceUSDT: nil
                ),
            ]
        }

        let credentials = try walletCredentials(walletID: walletID)
        MeshPrivacyStore.ensureDefaultReceiveSetup(walletID: credentials.walletID)
        return try MeshPrivacyStore.visibleReceiveSlotIndices(walletID: credentials.walletID).map { index in
            let address = try address(for: index, credentials: credentials)
            return WalletReceiveSlotOption(
                index: index,
                address: address,
                title: MeshPrivacyStore.receiveSlotDisplayTitle(
                    index: index,
                    walletID: credentials.walletID
                ),
                derivationPath: TronWalletService.receiveDerivationPath(accountIndex: index),
                balanceUSDT: nil
            )
        }
    }

    /// All five receive slots with on-chain USDT balance per address.
    static func listWalletReceiveSlotsWithBalances(
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) async throws -> [WalletReceiveSlotOption] {
        let resolvedWalletID = walletID
        var slots = try await Task.detached(priority: .userInitiated) {
            try listWalletReceiveSlots(walletID: resolvedWalletID)
        }.value
        guard !slots.isEmpty else { return slots }

        if slots.count == 1, let address = slots.first?.address {
            if let balance = await TronUSDTService.fetchUSDTBalance(address: address) {
                slots[0].balanceUSDT = balance
            }
            return slots
        }

        let gate = TronGridRequestGate.wallet
        var updated: [WalletReceiveSlotOption] = []
        updated.reserveCapacity(slots.count)
        await withTaskGroup(of: WalletReceiveSlotOption.self) { group in
            for slot in slots {
                group.addTask {
                    let balance = try? await gate.perform {
                        await TronUSDTService.fetchUSDTBalance(address: slot.address)
                    }
                    var copy = slot
                    copy.balanceUSDT = balance
                    return copy
                }
            }
            for await slot in group {
                updated.append(slot)
            }
        }
        return updated.sorted { $0.index < $1.index }
    }

    /// Spend source for a single slot only — never consolidates or mixes other addresses.
    static func resolveSpendSourceFromSlot(
        slotIndex: UInt32,
        requiredAmount: Decimal,
        walletID: String? = MeshWalletRegistry.activeWalletID,
        skipBalanceVerification: Bool = false
    ) async throws -> PrivacySpendSource {
        let credentials = try walletCredentials(walletID: walletID)
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)
        let index = min(max(slotIndex, 0), MeshPrivacyStore.walletReceiveSlotCount - 1)
        let source = try spendSource(for: index, credentials: credentials)

        if !skipBalanceVerification {
            guard let balance = try await TronGridRequestGate.wallet.perform({
                await TronUSDTService.fetchUSDTBalance(address: source.address)
            }) else {
                throw TronAPIError.broadcastFailed(
                    "Could not verify USDT balance. Check your connection and try again."
                )
            }
            guard balance >= requiredAmount else {
                throw TronAPIError.broadcastFailed(
                    "Not enough USDT on \(MeshPrivacyStore.receiveSlotTitle(index: index))."
                )
            }
        }
        if !MeshNetworkSponsorship.isEnabled, !skipBalanceVerification {
            let resources = try await TronUSDTService.fetchResources(address: source.address)
            guard resources.hasEnoughTRXForFees else {
                throw TronAPIError.insufficientTRXForFee
            }
        }
        return source
    }

    /// Receive QR/address for the selected slot (defaults to last used).
    static func prepareReceiveContext(
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) throws -> PrivacyReceiveContext {
        try receiveContext(
            slotIndex: MeshPrivacyStore.selectedReceiveSlotIndex(walletID: walletID),
            walletID: walletID
        )
    }

    static func selectReceiveSlot(
        _ slotIndex: UInt32,
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) throws -> PrivacyReceiveContext {
        let context = try receiveContext(slotIndex: slotIndex, walletID: walletID)
        if let walletID = walletID ?? MeshWalletRegistry.activeWalletID {
            MeshPrivacyStore.setSelectedWalletSlotIndex(context.accountIndex, walletID: walletID)
        }
        return context
    }

    private static func receiveContext(
        slotIndex: UInt32,
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) throws -> PrivacyReceiveContext {
        if !MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) {
            let resolved = try MeshWalletCredentials.resolve(walletID: walletID)
            return PrivacyReceiveContext(
                address: resolved.address,
                accountIndex: 0,
                isPrivateMode: false,
                paymentNumber: 1
            )
        }

        let credentials = try walletCredentials(walletID: walletID)
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)
        let index = min(max(slotIndex, 0), MeshPrivacyStore.walletReceiveSlotCount - 1)
        let address = try address(for: index, credentials: credentials)
        return PrivacyReceiveContext(
            address: address,
            accountIndex: index,
            isPrivateMode: index > 0,
            paymentNumber: Int(index + 1)
        )
    }

    // MARK: - Send

    static func anyAddressHasTRXForFees(walletID: String? = MeshWalletRegistry.activeWalletID) async -> Bool {
        guard let credentials = try? walletCredentials(walletID: walletID) else { return false }
        let indices = MeshPrivacyStore.monitoredReceiveIndices(walletID: credentials.walletID)
        for index in indices {
            guard let address = try? address(for: index, credentials: credentials),
                  let resources = try? await TronUSDTService.fetchResources(address: address),
                  resources.hasEnoughTRXForFees
            else { continue }
            return true
        }
        return false
    }

    /// Merged TRC-20 activity across main + registered derived receive addresses.
    /// Pass `slotIndex` to load a single receive slot only (home address picker).
    static func fetchActivityHistory(
        limit: Int = 50,
        slotIndex: UInt32? = nil,
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) async throws -> [TronUSDTTransaction] {
        guard MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) else {
            let address = try MeshWalletCredentials.resolve(walletID: walletID).address
            return try await TronUSDTService.fetchTransactions(address: address, limit: limit)
        }

        let credentials = try walletCredentials(walletID: walletID)
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)

        if let slotIndex {
            let index = min(max(slotIndex, 0), MeshPrivacyStore.walletReceiveSlotCount - 1)
            let address = try address(for: index, credentials: credentials)
            return try await TronUSDTService.fetchTransactions(address: address, limit: limit)
        }

        let indices = MeshPrivacyStore.visibleReceiveSlotIndices(walletID: credentials.walletID)
        let perAddressLimit = min(20, max(6, limit / max(indices.count, 1) + 2))
        var merged: [TronUSDTTransaction] = []
        var seenTxIDs = Set<String>()
        var lastError: Error?
        var successCount = 0

        await withTaskGroup(of: (success: Bool, batch: [TronUSDTTransaction], error: Error?).self) { group in
            for index in indices {
                group.addTask {
                    do {
                        let address = try address(for: index, credentials: credentials)
                        let batch = try await TronUSDTService.fetchTransactions(
                            address: address,
                            limit: perAddressLimit
                        )
                        return (true, batch, nil)
                    } catch {
                        return (false, [], error)
                    }
                }
            }
            for await result in group {
                if result.success {
                    successCount += 1
                    for tx in result.batch where seenTxIDs.insert(tx.txID).inserted {
                        merged.append(tx)
                    }
                } else if lastError == nil {
                    lastError = result.error
                }
            }
        }

        if merged.isEmpty, successCount == 0, let lastError {
            throw lastError
        }

        return merged
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    private enum FundedIndexSyncMode {
        case fast
        case restoreBounded
        case deepRecovery
    }

    /// Registers receive indices that currently hold USDT (restore / send prep).
    static func syncFundedReceiveIndicesFromChain(
        walletID: String? = MeshWalletRegistry.activeWalletID,
        deepRecovery: Bool = false
    ) async {
        let mode: FundedIndexSyncMode = deepRecovery ? .deepRecovery : .fast
        await syncFundedReceiveIndicesFromChain(walletID: walletID, mode: mode)
    }

    private static func syncFundedReceiveIndicesFromChain(
        walletID: String? = MeshWalletRegistry.activeWalletID,
        mode: FundedIndexSyncMode
    ) async {
        guard MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) else { return }
        guard let credentials = try? walletCredentials(walletID: walletID) else { return }

        MeshPrivacyStore.registerReceiveIndex(0, walletID: credentials.walletID)

        let next = MeshPrivacyStore.peekNextReceiveAccountIndex(walletID: credentials.walletID)
        let registered = MeshPrivacyStore.registeredReceiveIndices(walletID: credentials.walletID)
        let highestRegistered = registered.max() ?? 0
        let minimumUpperBound = max(next + 1, highestRegistered + 2, mode == .deepRecovery ? 64 : 8)
        let hardUpperBound: UInt32 = {
            switch mode {
            case .fast: 48
            case .restoreBounded: MeshPrivacyStore.walletReceiveSlotCount - 1
            case .deepRecovery: MeshPrivacyStore.deepRecoveryScanMaxIndex
            }
        }()
        let emptyGapStop: Int = {
            switch mode {
            case .fast: 20
            case .restoreBounded: 10
            case .deepRecovery: Int.max
            }
        }()
        let gapChecksStartAt = mode == .restoreBounded ? UInt32(8) : minimumUpperBound

        if mode == .fast {
            MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)
            let candidates = MeshPrivacyStore.walletReceiveSlotIndices()

            for (offset, idx) in candidates.enumerated() {
                if offset > 0 {
                    try? await Task.sleep(nanoseconds: 8_000_000)
                }
                guard let address = try? address(for: idx, credentials: credentials),
                      let balance = await TronUSDTService.fetchUSDTBalance(address: address),
                      balance > 0
                else { continue }
                MeshPrivacyStore.registerReceiveIndex(idx, walletID: credentials.walletID)
                MeshPrivacyStore.ensureNextReceiveIndexAbove(idx, walletID: credentials.walletID)
            }
            return
        }

        if mode == .restoreBounded {
            await syncRestoreBoundedFundedIndices(
                credentials: credentials,
                hardUpperBound: hardUpperBound,
                gapChecksStartAt: gapChecksStartAt,
                emptyGapStop: emptyGapStop
            )
            return
        }

        await syncDeepRecoveryFundedIndices(
            credentials: credentials,
            hardUpperBound: hardUpperBound
        )
    }

    enum DeepRecoveryProgress: Sendable {
        case scanning(checked: Int, total: Int)
        case transferring(current: Int, total: Int)
    }

    /// Privacy-only: throttled scan of 1024 receive indices (0…1023).
    private static func syncDeepRecoveryFundedIndices(
        credentials: WalletCredentials,
        hardUpperBound: UInt32,
        onProgress: (@MainActor @Sendable (DeepRecoveryProgress) -> Void)? = nil
    ) async {
        let total = Int(MeshPrivacyStore.deepRecoveryScanAddressCount)
        let gate = TronGridRequestGate.deepRecovery

        if let onProgress {
            await MainActor.run {
                onProgress(.scanning(checked: 0, total: total))
            }
        }

        for index in UInt32(0)...hardUpperBound {
            if index > 0, index % 4 == 0 {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }

            await scanDeepRecoveryIndex(
                index: index,
                credentials: credentials,
                gate: gate
            )

            let checked = Int(index) + 1
            if let onProgress, checked % 4 == 0 || index == hardUpperBound {
                await MainActor.run {
                    onProgress(.scanning(checked: checked, total: total))
                }
            }
        }
    }

    private static func scanDeepRecoveryIndex(
        index: UInt32,
        credentials: WalletCredentials,
        gate: TronGridRequestGate
    ) async {
        let balance: Decimal? = try? await gate.perform {
            let address = try address(for: index, credentials: credentials)
            return await TronUSDTService.fetchUSDTBalance(address: address)
        }
        guard let balance, balance > 0 else { return }
        MeshPrivacyStore.registerReceiveIndex(index, walletID: credentials.walletID)
        MeshPrivacyStore.ensureNextReceiveIndexAbove(index, walletID: credentials.walletID)
    }

    /// Bounded post-restore sweep (parallel batches) — only the five receive slots.
    private static func syncRestoreBoundedFundedIndices(
        credentials: WalletCredentials,
        hardUpperBound: UInt32,
        gapChecksStartAt: UInt32,
        emptyGapStop: Int
    ) async {
        let batchSize: UInt32 = 8
        var consecutiveEmptyAfterMinimum = 0
        var index: UInt32 = 0

        while index <= hardUpperBound {
            let batchEnd = min(index + batchSize - 1, hardUpperBound)
            var batchResults: [(UInt32, Bool)] = []
            batchResults.reserveCapacity(Int(batchEnd - index + 1))

            await withTaskGroup(of: (UInt32, Bool).self) { group in
                for i in index...batchEnd {
                    group.addTask {
                        guard let address = try? address(for: i, credentials: credentials),
                              let balance = await TronUSDTService.fetchUSDTBalance(address: address),
                              balance > 0
                        else {
                            return (i, false)
                        }
                        MeshPrivacyStore.registerReceiveIndex(i, walletID: credentials.walletID)
                        MeshPrivacyStore.ensureNextReceiveIndexAbove(i, walletID: credentials.walletID)
                        return (i, true)
                    }
                }
                for await result in group {
                    batchResults.append(result)
                }
            }

            for (offset, entry) in batchResults.sorted(by: { $0.0 < $1.0 }).enumerated() {
                if offset > 0 {
                    try? await Task.sleep(nanoseconds: 4_000_000)
                }
                let (idx, hasFunds) = entry
                if idx >= gapChecksStartAt {
                    consecutiveEmptyAfterMinimum = hasFunds ? 0 : (consecutiveEmptyAfterMinimum + 1)
                    if consecutiveEmptyAfterMinimum >= emptyGapStop {
                        return
                    }
                }
            }

            index = batchEnd + 1
        }
    }

    /// Maps on-chain activity addresses to receive indices (no API calls).
    static func registerReceiveIndicesFromActivity(
        transactions: [TronUSDTTransaction],
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) {
        guard MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) else { return }
        guard let credentials = try? walletCredentials(walletID: walletID) else { return }

        MeshPrivacyStore.registerReceiveIndex(0, walletID: credentials.walletID)
        var candidates = Set<String>()
        for tx in transactions {
            candidates.insert(tx.fromAddress)
            candidates.insert(tx.toAddress)
        }

        for address in candidates where !address.isEmpty {
            guard let index = receiveIndex(
                matching: address,
                credentials: credentials,
                maxIndex: MeshPrivacyStore.walletReceiveSlotCount - 1
            ) else { continue }
            MeshPrivacyStore.registerReceiveIndex(index, walletID: credentials.walletID)
            MeshPrivacyStore.ensureNextReceiveIndexAbove(index, walletID: credentials.walletID)
        }
    }

    private static func receiveIndex(
        matching targetAddress: String,
        credentials: WalletCredentials,
        maxIndex: UInt32
    ) -> UInt32? {
        for index in 0...maxIndex {
            guard let derived = try? address(for: index, credentials: credentials),
                  TronAddressCodec.matches(derived, targetAddress)
            else { continue }
            return index
        }
        return nil
    }

    /// Total USDT across the five receive slots (indices 0…4).
    static func totalAvailableUSDT(
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) async throws -> Decimal {
        try await fiveReceiveSlotsUSDTTotal(walletID: walletID)
    }

    enum BalanceFetchMode {
        case full
        case light
    }

    /// Sum of on-chain USDT on receive slots 0…4 (parallel fetch, no deep scan).
    static func fiveReceiveSlotsUSDTTotal(
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) async throws -> Decimal {
        try await fiveReceiveSlotsUSDTTotalDetailed(walletID: walletID).total
    }

    static func fiveReceiveSlotsUSDTTotalDetailed(
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) async throws -> (total: Decimal, isCompleteRead: Bool) {
        let credentials = try walletCredentials(walletID: walletID)
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)
        let indices = MeshPrivacyStore.walletReceiveSlotIndices()
        let aggregate = await aggregateTotalUSDT(
            indices: indices,
            credentials: credentials
        )
        guard aggregate.successfulReads > 0 else {
            throw TronAPIError.broadcastFailed("Could not read USDT balance.")
        }
        return (
            aggregate.total,
            aggregate.successfulReads == aggregate.attemptedReads
        )
    }

    /// Same as `fiveReceiveSlotsUSDTTotalDetailed` (kept for home/send callers).
    static func totalAvailableUSDTDetailed(
        walletID: String? = MeshWalletRegistry.activeWalletID,
        skipRestoreDiscovery: Bool = false,
        fetchMode: BalanceFetchMode = .full
    ) async throws -> (total: Decimal, isCompleteRead: Bool) {
        _ = skipRestoreDiscovery
        _ = fetchMode
        return try await fiveReceiveSlotsUSDTTotalDetailed(walletID: walletID)
    }

    /// Validates that a separated (relay) send can be funded.
    /// Receive address for a slot index (no balance check).
    static func receiveAddress(
        slotIndex: UInt32,
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) throws -> String {
        let credentials = try walletCredentials(walletID: walletID)
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)
        let index = min(max(slotIndex, 0), MeshPrivacyStore.walletReceiveSlotCount - 1)
        return try address(for: index, credentials: credentials)
    }

    static func validateSeparatedSend(
        amount: Decimal,
        networkFee: Decimal,
        mode: MeshPrivateSendMode,
        slotIndex: UInt32? = nil,
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) async throws -> (funding: PrivacySpendSource, relayPreview: String, hopCount: Int) {
        if MeshSendFees.showsFeeInUI, networkFee > 0, amount <= networkFee {
            throw TronAPIError.broadcastFailed(
                L10n.Error.amountBelowFee(MeshSendFees.formattedFee(networkFee))
            )
        }
        let credentials = try walletCredentials(walletID: walletID)
        let hops = mode.relayHopCount
        let totalRequired = MeshSendFees.chargesOnChainFee ? amount + networkFee : amount
        let sendSlot = slotIndex ?? MeshPrivacyStore.selectedWalletSlotIndex(walletID: credentials.walletID)
        let funding = try await resolveSpendSourceFromSlot(
            slotIndex: sendSlot,
            requiredAmount: totalRequired,
            walletID: credentials.walletID
        )
        guard let fundingUSDT = await TronUSDTService.fetchUSDTBalance(address: funding.address) else {
            throw TronAPIError.broadcastFailed(
                "Could not verify USDT balance. Check your connection and try again."
            )
        }
        guard fundingUSDT >= totalRequired else {
            throw TronAPIError.broadcastFailed("Not enough USDT on your wallet.")
        }
        if !MeshNetworkSponsorship.isEnabled {
            let fundingAccount = await TronUSDTService.fetchBalance(address: funding.address)
            guard fundingAccount.trxBalance >= TronConfiguration.relayFundingMinTRX(hopCount: hops) else {
                throw TronAPIError.insufficientTRXForFee
            }
        }
        let lastRelayIndex = MeshPrivacyStore.peekRelayAccountIndex(walletID: credentials.walletID)
            + UInt32(hops - 1)
        let relayAddress = try TronWalletService.deriveRelayAddress(
            accountIndex: lastRelayIndex,
            words: credentials.words,
            passphrase: credentials.passphrase
        )
        return (funding, relayAddress, hops)
    }

    /// Picks a receive address with enough USDT.
    /// - `discoverFundedIndices`: scan chain for unknown funded indices (home balance).
    /// - `preferNewestFunded`: stop at the first sufficient address, newest index first (send handoff).
    static func resolveSpendSource(
        requiredAmount: Decimal,
        walletID: String? = MeshWalletRegistry.activeWalletID,
        discoverFundedIndices: Bool = false,
        preferNewestFunded: Bool = false
    ) async throws -> PrivacySpendSource {
        let credentials = try walletCredentials(walletID: walletID)
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)
        if discoverFundedIndices {
            await syncFundedReceiveIndicesFromChain(walletID: credentials.walletID, mode: .fast)
        }

        let indices = MeshPrivacyStore.walletReceiveSlotIndices()
        let scanOrder = preferNewestFunded ? indices.sorted(by: >) : indices

        var slotBalances: [(index: UInt32, balance: Decimal)] = []
        for (offset, index) in scanOrder.enumerated() {
            if offset > 0 {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            let address = try address(for: index, credentials: credentials)
            guard let available = try await TronGridRequestGate.wallet.perform({
                await TronUSDTService.fetchUSDTBalance(address: address)
            }) else { continue }
            slotBalances.append((index, available))
        }

        let totalUSDT = slotBalances.reduce(Decimal(0)) { $0 + $1.balance }
        guard totalUSDT >= requiredAmount else {
            throw TronAPIError.broadcastFailed(
                "Not enough USDT on your wallet for this transfer and network fee."
            )
        }

        var spendable: [(index: UInt32, balance: Decimal)] = []
        for entry in slotBalances where entry.balance > 0 {
            if !MeshNetworkSponsorship.isEnabled {
                let address = try address(for: entry.index, credentials: credentials)
                let resources = try await TronUSDTService.fetchResources(address: address)
                guard resources.hasEnoughTRXForFees else { continue }
            }
            spendable.append(entry)
        }

        if let sufficient = spendable
            .filter({ $0.balance >= requiredAmount })
            .max(by: { $0.balance < $1.balance })
        {
            return try spendSource(for: sufficient.index, credentials: credentials)
        }

        try await consolidateReceiveSlotsToMain(
            requiredAmount: requiredAmount,
            credentials: credentials
        )

        if let main = try await spendSourceIfSufficient(
            index: 0,
            requiredAmount: requiredAmount,
            credentials: credentials
        ) {
            return main
        }

        throw TronAPIError.broadcastFailed(
            "Not enough USDT on your wallet for this transfer and network fee."
        )
    }

    /// Privacy-only: one-time deep chain scan, then sends all non-main USDT to index 0.
    static func recoverDeepFundsToMainWallet(
        walletID: String? = MeshWalletRegistry.activeWalletID,
        onProgress: (@MainActor @Sendable (DeepRecoveryProgress) -> Void)? = nil
    ) async throws -> Int {
        let credentials = try walletCredentials(walletID: walletID)
        await syncDeepRecoveryFundedIndices(
            credentials: credentials,
            hardUpperBound: MeshPrivacyStore.deepRecoveryScanMaxIndex,
            onProgress: onProgress
        )

        let mainAddress = try address(for: 0, credentials: credentials)
        var donorIndices = Set(MeshPrivacyStore.registeredReceiveIndices(walletID: credentials.walletID))
        donorIndices.remove(0)

        var donors: [(index: UInt32, balance: Decimal)] = []
        let gate = TronGridRequestGate.deepRecovery
        for index in donorIndices.sorted() {
            let address = try address(for: index, credentials: credentials)
            guard let balance = try await gate.perform({
                await TronUSDTService.fetchUSDTBalance(address: address)
            }),
                  balance > 0
            else { continue }
            donors.append((index: index, balance: balance))
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        donors.sort { $0.balance > $1.balance }

        let transferTotal = donors.count
        if let onProgress {
            await MainActor.run {
                onProgress(.transferring(current: 0, total: transferTotal))
            }
        }

        var transferCount = 0
        for (offset, donor) in donors.enumerated() {
            if offset > 0 {
                try await Task.sleep(nanoseconds: 1_200_000_000)
            }
            let source = try spendSource(for: donor.index, credentials: credentials)
            _ = try await sendUSDTWithRateLimitRetry(
                to: mainAddress,
                amount: donor.balance,
                spendSource: source
            )
            transferCount += 1
            if let onProgress {
                await MainActor.run {
                    onProgress(.transferring(current: transferCount, total: transferTotal))
                }
            }
        }

        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)
        return transferCount
    }

    /// Moves full USDT balances from receive slots 1…4 into slot 0 (main).
    static func consolidateFiveReceiveSlotsToMainWallet(
        walletID: String? = MeshWalletRegistry.activeWalletID,
        onProgress: (@MainActor @Sendable (_ current: Int, _ total: Int) -> Void)? = nil
    ) async throws -> Int {
        let credentials = try walletCredentials(walletID: walletID)
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: credentials.walletID)
        let mainAddress = try address(for: 0, credentials: credentials)
        let gate = TronGridRequestGate.wallet

        var donors: [(index: UInt32, balance: Decimal)] = []
        for index in MeshPrivacyStore.walletReceiveSlotIndices() where index > 0 {
            let address = try address(for: index, credentials: credentials)
            guard let balance = try await gate.perform({
                await TronUSDTService.fetchUSDTBalance(address: address)
            }),
                  balance > 0
            else { continue }
            donors.append((index: index, balance: balance))
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        donors.sort { $0.balance > $1.balance }

        let transferTotal = donors.count
        if let onProgress {
            await MainActor.run { onProgress(0, transferTotal) }
        }

        var transferCount = 0
        for (offset, donor) in donors.enumerated() {
            if offset > 0 {
                try await Task.sleep(nanoseconds: 1_200_000_000)
            }
            let source = try spendSource(for: donor.index, credentials: credentials)
            _ = try await sendUSDTWithRateLimitRetry(
                to: mainAddress,
                amount: donor.balance,
                spendSource: source
            )
            transferCount += 1
            if let onProgress {
                await MainActor.run { onProgress(transferCount, transferTotal) }
            }
        }
        return transferCount
    }

    /// Moves USDT from derived addresses into slot 0 until the main address can cover `requiredAmount`.
    private static func consolidateReceiveSlotsToMain(
        requiredAmount: Decimal,
        credentials: WalletCredentials
    ) async throws {
        let mainAddress = try address(for: 0, credentials: credentials)
        var mainBalance = await TronUSDTService.fetchUSDTBalance(address: mainAddress) ?? 0
        guard mainBalance < requiredAmount else { return }

        var donors = try await donorsSortedByBalance(
            credentials: credentials,
            excludingMain: true
        )

        for donor in donors {
            guard mainBalance < requiredAmount else { return }
            let shortfall = requiredAmount - mainBalance
            let transferAmount = min(donor.balance, shortfall)
            guard transferAmount > 0 else { continue }

            let source = try spendSource(for: donor.index, credentials: credentials)
            _ = try await TronUSDTService.sendUSDT(
                to: mainAddress,
                amount: transferAmount,
                spendSource: source
            )
            mainBalance += transferAmount
        }

        guard mainBalance >= requiredAmount else {
            throw TronAPIError.broadcastFailed(
                "Not enough USDT on your wallet for this transfer and network fee."
            )
        }
    }

    private static func donorsSortedByBalance(
        credentials: WalletCredentials,
        excludingMain: Bool
    ) async throws -> [(index: UInt32, balance: Decimal)] {
        var donors: [(index: UInt32, balance: Decimal)] = []
        for index in MeshPrivacyStore.walletReceiveSlotIndices() where !excludingMain || index > 0 {
            let address = try address(for: index, credentials: credentials)
            guard let balance = await TronUSDTService.fetchUSDTBalance(address: address),
                  balance > 0
            else { continue }
            donors.append((index: index, balance: balance))
        }
        return donors.sorted { $0.balance > $1.balance }
    }

    private static func spendSource(
        for index: UInt32,
        credentials: WalletCredentials
    ) throws -> PrivacySpendSource {
        let address = try address(for: index, credentials: credentials)
        return PrivacySpendSource(
            address: address,
            derivationPath: TronWalletService.receiveDerivationPath(accountIndex: index),
            accountIndex: index,
            isPrivateSpend: index > 0
        )
    }

    private static func sendUSDTWithRateLimitRetry(
        to recipient: String,
        amount: Decimal,
        spendSource: PrivacySpendSource,
        maxAttempts: Int = 6
    ) async throws -> TronUSDTTransferResult {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await TronUSDTService.sendUSDT(
                    to: recipient,
                    amount: amount,
                    spendSource: spendSource
                )
            } catch {
                lastError = error
                guard isRateLimitError(error), attempt < maxAttempts - 1 else {
                    throw error
                }
                let delaySeconds = min(12, 1 + attempt * 2)
                try await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
        }
        throw lastError ?? TronAPIError.rateLimited
    }

    static func isRateLimitError(_ error: Error) -> Bool {
        if let tron = error as? TronAPIError, case .rateLimited = tron {
            return true
        }
        let lower = error.localizedDescription.lowercased()
        return lower.contains("429")
            || lower.contains("rate limit")
            || lower.contains("too many")
            || lower.contains("network is busy")
    }

    // MARK: - Private

    private struct WalletCredentials {
        let walletID: String
        let words: [String]
        let passphrase: String
    }

    private static func walletCredentials(walletID: String?) throws -> WalletCredentials {
        guard MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) else {
            throw TronAPIError.broadcastFailed(
                "Private key wallets do not support private send or one-time receive addresses."
            )
        }
        let resolved = try MeshWalletCredentials.resolve(walletID: walletID)
        guard let words = resolved.mnemonic else {
            throw TronAPIError.broadcastFailed("Wallet is not initialized")
        }
        return WalletCredentials(
            walletID: resolved.walletID,
            words: words,
            passphrase: resolved.passphrase
        )
    }

    private static func address(for index: UInt32, credentials: WalletCredentials) throws -> String {
        try TronWalletService.deriveReceiveAddress(
            accountIndex: index,
            words: credentials.words,
            passphrase: credentials.passphrase
        )
    }

    private static func spendSourceIfSufficient(
        index: UInt32,
        requiredAmount: Decimal,
        credentials: WalletCredentials
    ) async throws -> PrivacySpendSource? {
        let address = try address(for: index, credentials: credentials)
        guard let available = await TronUSDTService.fetchUSDTBalance(address: address) else {
            return nil
        }
        guard available >= requiredAmount else { return nil }

        if !MeshNetworkSponsorship.isEnabled {
            let resources = try await TronUSDTService.fetchResources(address: address)
            guard resources.hasEnoughTRXForFees else { return nil }
        }

        return PrivacySpendSource(
            address: address,
            derivationPath: TronWalletService.receiveDerivationPath(accountIndex: index),
            accountIndex: index,
            isPrivateSpend: index > 0
        )
    }

    private static let balanceFetchConcurrency = 3

    private static func aggregateTotalUSDT(
        indices: [UInt32],
        credentials: WalletCredentials
    ) async -> (total: Decimal, successfulReads: Int, attemptedReads: Int) {
        guard !indices.isEmpty else {
            return (0, 0, 0)
        }

        var total: Decimal = 0
        var successfulReads = 0
        var failedIndices: [UInt32] = []
        let reads = await fetchUSDTBalances(
            indices: indices,
            credentials: credentials
        )

        for (index, balance) in reads {
            if let balance {
                successfulReads += 1
                total += balance
            } else {
                failedIndices.append(index)
            }
        }

        if !failedIndices.isEmpty {
            let retries = await fetchUSDTBalances(
                indices: failedIndices,
                credentials: credentials
            )
            for (_, balance) in retries where balance != nil {
                successfulReads += 1
                total += balance!
            }
        }

        return (total, successfulReads, indices.count)
    }

    private static func fetchUSDTBalances(
        indices: [UInt32],
        credentials: WalletCredentials
    ) async -> [(UInt32, Decimal?)] {
        guard !indices.isEmpty else { return [] }

        var results: [(UInt32, Decimal?)] = []
        results.reserveCapacity(indices.count)
        let concurrency = balanceFetchConcurrency

        var start = 0
        while start < indices.count {
            let end = min(start + concurrency, indices.count)
            let slice = Array(indices[start..<end])
            start = end

            await withTaskGroup(of: (UInt32, Decimal?).self) { group in
                for index in slice {
                    group.addTask {
                        guard let address = try? address(for: index, credentials: credentials) else {
                            return (index, nil)
                        }
                        let balance = try? await TronGridRequestGate.wallet.perform {
                            await TronUSDTService.fetchUSDTBalance(address: address)
                        }
                        return (index, balance)
                    }
                }
                for await entry in group {
                    results.append(entry)
                }
            }
        }

        return results.sorted { $0.0 < $1.0 }
    }

    /// Fixed receive slots used for displayed wallet balance.
    private static func registeredBalanceIndices(walletID: String) -> [UInt32] {
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: walletID)
        return MeshPrivacyStore.walletReceiveSlotIndices()
    }

    private static func balanceScanIndices(walletID: String) -> [UInt32] {
        MeshPrivacyStore.ensureWalletReceiveSlots(walletID: walletID)
        return MeshPrivacyStore.walletReceiveSlotIndices()
    }

    /// Fast-path indices for UI balance/history refreshes.
    /// Uses registered indices + a small look-ahead window near the next receive index.
    private static func fastScanIndices(walletID: String) -> [UInt32] {
        var indices = Set<UInt32>([0])
        for value in MeshPrivacyStore.registeredReceiveIndices(walletID: walletID).suffix(48) {
            indices.insert(value)
        }
        let next = MeshPrivacyStore.peekNextReceiveAccountIndex(walletID: walletID)
        let lookahead: UInt32 = 24
        let start = next > lookahead ? (next - lookahead) : 0
        if next > 0 {
            for index in start..<next {
                indices.insert(index)
            }
        }
        let headUpper = min<UInt32>(12, next + 2)
        if headUpper > 0 {
            for index in UInt32(0)...headUpper {
                indices.insert(index)
            }
        }
        return indices.sorted()
    }
}
