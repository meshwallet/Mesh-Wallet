import Combine
import Foundation
import SwiftUI

@MainActor
final class WalletHomeViewModel: ObservableObject {
    private static let balanceCachePrefix = "mesh.wallet.balance.cached."
    @Published var walletAddress: String = ""
    @Published var usdtBalance: Decimal = 0
    @Published var transactions: [WalletTransaction] = []
    @Published var isLoading = false
    @Published var isBalanceLoading = false
    @Published private(set) var isHistoryLoading = false
    /// Active while `.refreshable` pull-to-refresh is in flight (spinner + balance feedback).
    @Published private(set) var isPullRefreshing = false
    /// 0…1 drive for post-refresh / wallet-switch settle animation.
    @Published private(set) var balanceSettlePhase: CGFloat = 0
    @Published private(set) var isBalanceStale = false
    @Published var loadError: String?
    @Published var receiveSlotBalances: [WalletReceiveSlotOption] = []
    /// Receive slot shown as the hero card and used to filter activity on home.
    @Published private(set) var focusedReceiveSlotIndex: UInt32 = 0

    private var refreshGeneration = 0
    /// Last on-chain USDT balance from TronGrid (before pending-send holds).
    private var chainBalanceByWalletID: [String: Decimal] = [:]
    /// Last displayed balance shown in the UI (chain minus pending holds).
    private var balanceByWalletID: [String: Decimal] = [:]
    /// Last merged history (all slots) per wallet — used to filter by focused slot.
    private var fullTransactionsByWalletID: [String: [WalletTransaction]] = [:]
    /// Cached filtered history per wallet + slot (`walletID:slotIndex`).
    private var slotTransactionsByWalletID: [String: [WalletTransaction]] = [:]
    /// Per-slot USDT cache so refresh does not flash Address 1 balance on other slots.
    private var slotBalanceCacheByWalletID: [String: [UInt32: Decimal]] = [:]
    private var backgroundPreloadTask: Task<Void, Never>?
    private var preparedWalletID: String?
    private var shouldAnimateNextBalanceApply = false
    /// Blocks multi-wallet preload until the first home `load()` finishes (avoids unlock jank).
    private var allowsBackgroundPreload = false

    var formattedBalance: String {
        Self.balanceFormatter.string(from: NSDecimalNumber(decimal: usdtBalance)) ?? "0.00"
    }

    /// Hero balance for the focused receive slot (home card stack).
    var focusedSlotFormattedBalance: String {
        if let balance = resolvedFocusedSlotBalance() {
            let text = Self.formatUSDT(balance)
            rememberFocusedHeroBalanceText(text)
            return text
        }
        if focusedReceiveSlotIndex == 0 {
            return formattedBalance
        }
        return lastFocusedHeroBalanceText() ?? "0.00"
    }

    /// Sum of all visible receive-slot balances (same rules as the former drawer total).
    var aggregatedReceiveSlotsUSDT: Decimal {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return usdtBalance }
        return receiveSlotBalances.reduce(into: Decimal.zero) { sum, slot in
            guard let chain = slot.balanceUSDT else { return }
            sum += displayAmount(forSlot: slot.index, chain: chain, walletID: walletID)
        }
    }

    /// Drawer slot rows — same displayed balance as the home hero (chain minus pending sends).
    var receiveSlotBalancesForDisplay: [WalletReceiveSlotOption] {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return receiveSlotBalances }
        return receiveSlotBalances.map { slot in
            guard let chain = slot.balanceUSDT else { return slot }
            let displayed = displayAmount(forSlot: slot.index, chain: chain, walletID: walletID)
            guard displayed != chain else { return slot }
            var copy = slot
            copy.balanceUSDT = displayed
            return copy
        }
    }

    /// More than one receive account — show wallet total in the header.
    var showsHomeMultiAccountChrome: Bool {
        guard let walletID = MeshWalletRegistry.activeWalletID,
              MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        else { return false }
        return MeshPrivacyStore.visibleReceiveAddressCount(walletID: walletID) > 1
    }

    /// HD wallets reserve multi-account chrome layout so adding an account does not jump the hero.
    var supportsHomeAccountLayout: Bool {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return false }
        return MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
    }

    /// Account name directly under the hero balance (HD wallets).
    var showsHomeAccountCaption: Bool {
        supportsHomeAccountLayout
    }

    var formattedWalletTotalUSDT: String {
        Self.formatUSDT(aggregatedReceiveSlotsUSDT)
    }

    var focusedAccountTitle: String {
        receiveSlotRenameDraft(for: focusedReceiveSlotIndex)
    }

    /// Main-screen hero: balance for the focused receive account.
    var heroFormattedBalance: String {
        focusedSlotFormattedBalance
    }

    private func resolvedFocusedSlotBalance() -> Decimal? {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return nil }

        if let slot = receiveSlotBalances.first(where: { $0.index == focusedReceiveSlotIndex }),
           let balance = slot.balanceUSDT
        {
            let displayed = displayAmount(forSlot: focusedReceiveSlotIndex, chain: balance, walletID: walletID)
            slotBalanceCacheByWalletID[walletID, default: [:]][focusedReceiveSlotIndex] = displayed
            return displayed
        }

        if let cached = slotBalanceCacheByWalletID[walletID]?[focusedReceiveSlotIndex] {
            return cached
        }

        if focusedReceiveSlotIndex == 0 {
            return usdtBalance
        }
        return nil
    }

    private func displayAmount(forSlot index: UInt32, chain: Decimal, walletID: String) -> Decimal {
        let address = receiveAddress(for: index, walletID: walletID) ?? ""
        let hold: Decimal
        if address.isEmpty {
            hold = index == 0
                ? MeshBackgroundSendService.shared.pendingBalanceHold(for: walletID, chainBalance: chain)
                : 0
        } else {
            hold = MeshBackgroundSendService.shared.pendingBalanceHold(
                for: walletID,
                spendFromAddress: address,
                chainBalance: chain
            )
        }
        return max(0, chain - hold)
    }

    private func rememberFocusedHeroBalanceText(_ text: String) {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return }
        heroBalanceTextCacheByWalletID[walletID, default: [:]][focusedReceiveSlotIndex] = text
    }

    private var heroBalanceTextCacheByWalletID: [String: [UInt32: String]] = [:]

    private func lastFocusedHeroBalanceText() -> String? {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return nil }
        return heroBalanceTextCacheByWalletID[walletID]?[focusedReceiveSlotIndex]
    }

    private static func formatUSDT(_ amount: Decimal) -> String {
        balanceFormatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0.00"
    }

    /// Receive slots 1…4 shown under the main balance on home.
    var otherReceiveSlots: [WalletReceiveSlotOption] {
        receiveSlotBalances.filter { $0.index > 0 }
    }

    func selectHomeReceiveSlot(_ index: UInt32, animated: Bool = true) {
        let clamped = min(max(index, 0), MeshPrivacyStore.walletReceiveSlotCount - 1)
        if clamped == focusedReceiveSlotIndex {
            syncDisplayedBalanceWithFocusedSlot(animated: animated)
            applyDisplayedTransactionsForFocusedSlot()
            return
        }

        focusedReceiveSlotIndex = clamped
        if let walletID = MeshWalletRegistry.activeWalletID {
            MeshPrivacyStore.setSelectedWalletSlotIndex(clamped, walletID: walletID)
        }
        applyDisplayedTransactionsForFocusedSlot()
        syncDisplayedBalanceWithFocusedSlot(animated: false)

        guard let walletID = MeshWalletRegistry.activeWalletID else { return }
        let cacheKey = slotHistoryCacheKey(walletID: walletID, slotIndex: clamped)
        refreshGeneration += 1
        let generation = refreshGeneration
        Task { await reloadFocusedSlotHistory(generation: generation, cacheKey: cacheKey) }
    }

    /// After Receive / Send — home hero + history follow the slot stored in `MeshPrivacyStore`.
    func syncFocusedSlotFromStore() {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return }
        selectHomeReceiveSlot(MeshPrivacyStore.selectedWalletSlotIndex(walletID: walletID))
    }

    /// Apply slot picked on Receive/Send without network refresh or balance animation.
    func applyFocusedSlotFromStoreIfNeeded() {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return }
        let stored = MeshPrivacyStore.selectedWalletSlotIndex(walletID: walletID)
        guard stored != focusedReceiveSlotIndex else { return }

        focusedReceiveSlotIndex = stored
        applyDisplayedTransactionsForFocusedSlot()
        syncDisplayedBalanceWithFocusedSlot(animated: false)

        guard MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) else { return }
        let cacheKey = slotHistoryCacheKey(walletID: walletID, slotIndex: stored)
        guard slotTransactionsByWalletID[cacheKey] == nil else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        Task { await reloadFocusedSlotHistory(generation: generation, cacheKey: cacheKey) }
    }

    func refreshReceiveSlotsIfNeeded() async {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return }
        guard let slots = try? await MeshPrivacyService.listWalletReceiveSlotsWithBalances(
            walletID: walletID
        ) else { return }
        receiveSlotBalances = mergeSlotBalancesPreservingKnown(
            newSlots: slots,
            walletID: walletID
        )
    }

    private func syncDisplayedBalanceWithFocusedSlot(animated: Bool) {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return }

        if let displayed = resolvedFocusedSlotBalance() {
            let chain = receiveSlotBalances
                .first(where: { $0.index == focusedReceiveSlotIndex })?
                .balanceUSDT ?? displayed
            presentHeroBalance(
                displayed: displayed,
                chain: chain,
                animated: animated,
                forcePresentation: animated
            )
            return
        }

        if focusedReceiveSlotIndex == 0, let chain = chainBalanceByWalletID[walletID] {
            let displayed = displayAmount(forSlot: 0, chain: chain, walletID: walletID)
            presentHeroBalance(
                displayed: displayed,
                chain: chain,
                animated: animated,
                forcePresentation: animated
            )
        }
    }

    private var usesFocusedSlotHeroBalance: Bool {
        guard let walletID = MeshWalletRegistry.activeWalletID,
              MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        else { return false }
        return !receiveSlotBalances.isEmpty
    }

    private func recordMainChainBalance(chain: Decimal, walletID: String) {
        let displayed = displayAmount(forSlot: 0, chain: chain, walletID: walletID)
        chainBalanceByWalletID[walletID] = chain
        balanceByWalletID[walletID] = displayed
        slotBalanceCacheByWalletID[walletID, default: [:]][0] = displayed
        UserDefaults.standard.set(
            NSDecimalNumber(decimal: displayed).stringValue,
            forKey: Self.balanceCachePrefix + walletID
        )
        if let slotIdx = receiveSlotBalances.firstIndex(where: { $0.index == 0 }) {
            var slots = receiveSlotBalances
            var slot = slots[slotIdx]
            slot.balanceUSDT = chain
            slots[slotIdx] = slot
            receiveSlotBalances = slots
        }
    }

    private func presentHeroBalance(
        displayed: Decimal,
        chain: Decimal,
        animated: Bool,
        forcePresentation: Bool = false
    ) {
        let displayChanged = usdtBalance != displayed
        guard displayChanged || forcePresentation else { return }

        let apply = { [self] in
            usdtBalance = displayed
        }

        if animated && forcePresentation {
            playWalletStyleBalanceAnimation(
                displayed: displayed,
                chain: chain,
                walletID: MeshWalletRegistry.activeWalletID
            )
        } else if displayChanged {
            apply()
        }

        if displayChanged, !isLoading, !isPullRefreshing {
            NotificationCenter.default.post(name: .meshWalletBalancesShouldRefresh, object: nil)
        }
    }

    var canAddHomeReceiveAddress: Bool {
        guard let walletID = MeshWalletRegistry.activeWalletID,
              MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        else { return false }
        let maxSlots = Int(MeshPrivacyStore.walletReceiveSlotCount)
        return MeshPrivacyStore.visibleReceiveAddressCount(walletID: walletID)
            < MeshPrivacyStore.walletReceiveSlotCount
            && receiveSlotBalances.count < maxSlots
    }

    func renameHomeReceiveAccount(at index: UInt32, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let walletID = MeshWalletRegistry.activeWalletID
        else { return }

        MeshPrivacyStore.setReceiveSlotCustomName(trimmed, index: index, walletID: walletID)
        receiveSlotBalances = receiveSlotBalances.map { slot in
            guard slot.index == index else { return slot }
            return WalletReceiveSlotOption(
                index: slot.index,
                address: slot.address,
                title: MeshPrivacyStore.receiveSlotDisplayTitle(
                    index: slot.index,
                    walletID: walletID
                ),
                derivationPath: slot.derivationPath,
                balanceUSDT: slot.balanceUSDT
            )
        }
        invalidateSlotHistoryCaches(walletID: walletID)
    }

    func receiveSlotRenameDraft(for index: UInt32) -> String {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return "" }
        return MeshPrivacyStore.receiveSlotDisplayTitle(index: index, walletID: walletID)
    }

    func addHomeReceiveAddress(customName: String) async {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let walletID = MeshWalletRegistry.activeWalletID,
              let newIndex = MeshPrivacyStore.addReceiveAddress(walletID: walletID)
        else { return }

        MeshPrivacyStore.setReceiveSlotCustomName(trimmed, index: newIndex, walletID: walletID)

        refreshGeneration += 1
        let generation = refreshGeneration
        guard let slots = try? await MeshPrivacyService.listWalletReceiveSlotsWithBalances(
            walletID: walletID
        ) else { return }
        guard generation == refreshGeneration else { return }

        withAnimation(MeshBalanceRevealAnimation.listExpand) {
            receiveSlotBalances = mergeSlotBalancesPreservingKnown(
                newSlots: slots,
                walletID: walletID
            )
            selectHomeReceiveSlot(newIndex, animated: false)
        }

    }

    func removeHomeReceiveAddress(at index: UInt32) async {
        guard index > 0,
              let walletID = MeshWalletRegistry.activeWalletID,
              MeshPrivacyStore.removeReceiveAddress(at: index, walletID: walletID)
        else { return }

        purgeReceiveSlotCaches(for: index, walletID: walletID)

        refreshGeneration += 1
        let generation = refreshGeneration
        let focusIndex = MeshPrivacyStore.selectedWalletSlotIndex(walletID: walletID)

        guard let slots = try? await MeshPrivacyService.listWalletReceiveSlotsWithBalances(
            walletID: walletID
        ) else { return }
        guard generation == refreshGeneration else { return }

        receiveSlotBalances = mergeSlotBalancesPreservingKnown(
            newSlots: slots,
            walletID: walletID
        )
        focusedReceiveSlotIndex = focusIndex
        applyDisplayedTransactionsForFocusedSlot()
        syncDisplayedBalanceWithFocusedSlot(animated: false)
    }

    private func purgeReceiveSlotCaches(for index: UInt32, walletID: String) {
        slotBalanceCacheByWalletID[walletID]?.removeValue(forKey: index)
        heroBalanceTextCacheByWalletID[walletID]?.removeValue(forKey: index)
        slotTransactionsByWalletID.removeValue(
            forKey: slotHistoryCacheKey(walletID: walletID, slotIndex: index)
        )
    }

    func receiveSlotTitle(for index: UInt32) -> String {
        if let slot = receiveSlotBalances.first(where: { $0.index == index }) {
            return slot.title
        }
        return MeshPrivacyStore.receiveSlotDisplayTitle(
            index: index,
            walletID: MeshWalletRegistry.activeWalletID
        )
    }

    func receiveSlotDeleteAlertMessage(for index: UInt32) -> String {
        let title = receiveSlotTitle(for: index)
        let path = receiveSlotBalances.first(where: { $0.index == index })?.derivationPath
            ?? TronWalletService.receiveDerivationPath(accountIndex: index)
        return "\(L10n.Receive.deleteAddressMessage(title))\n\n\(path)"
    }

    func suggestedNewBalanceName() -> String {
        guard let walletID = MeshWalletRegistry.activeWalletID else {
            return L10n.WalletAddressDrawer.balanceSlot(2)
        }
        let nextNumber = Int(MeshPrivacyStore.visibleReceiveAddressCount(walletID: walletID)) + 1
        return L10n.WalletAddressDrawer.balanceSlot(nextNumber)
    }

    /// Opacity while the active wallet’s balance is refreshing (wallet switch / pull-to-refresh).
    var balanceDisplayOpacity: Double {
        isBalanceStale ? 0.42 : 1
    }

    /// Call when the active wallet changes — shows cached balance immediately when available.
    func prepareForWallet(id: String) {
        let walletChanged = preparedWalletID != nil && preparedWalletID != id
        preparedWalletID = id
        isBalanceLoading = false
        loadError = nil

        MeshBackgroundSendService.shared.restoreForActiveWallet()
        MeshBackgroundSendService.shared.releaseOrphanPendingHolds()

        if balanceByWalletID[id] == nil, let disk = Self.cachedBalanceFromDisk(walletID: id) {
            balanceByWalletID[id] = disk
        }

        focusedReceiveSlotIndex = MeshPrivacyStore.selectedReceiveSlotIndex(walletID: id)
        if let cached = slotTransactionsByWalletID[slotHistoryCacheKey(walletID: id, slotIndex: focusedReceiveSlotIndex)] {
            transactions = cached
        } else {
            transactions = []
        }

        if walletChanged {
            refreshGeneration += 1
            shouldAnimateNextBalanceApply = true
        }

        if MeshWalletCredentials.supportsHDWalletFeatures(walletID: id) {
            receiveSlotBalances = mergeSlotBalancesPreservingKnown(
                newSlots: quickReceiveSlotPlaceholders(walletID: id),
                walletID: id
            )
            Task { await hydrateReceiveSlotAddresses(walletID: id) }
        } else {
            receiveSlotBalances = []
        }

        if let chain = chainBalanceByWalletID[id] {
            isBalanceStale = false
            if walletChanged {
                recordMainChainBalance(chain: chain, walletID: id)
                let heroDisplayed = resolvedFocusedSlotBalance()
                    ?? displayAmount(forSlot: 0, chain: chain, walletID: id)
                let heroChain = receiveSlotBalances
                    .first(where: { $0.index == focusedReceiveSlotIndex })?
                    .balanceUSDT ?? chain
                playWalletStyleBalanceAnimation(
                    displayed: heroDisplayed,
                    chain: heroChain,
                    walletID: id
                )
            } else {
                applyDisplayedBalance(
                    chain: chain,
                    walletID: id,
                    animated: false,
                    isCompleteRead: true
                )
            }
        } else if let cached = balanceByWalletID[id] {
            isBalanceStale = true
            if walletChanged {
                let heroDisplayed = resolvedFocusedSlotBalance() ?? cached
                let heroChain = receiveSlotBalances
                    .first(where: { $0.index == focusedReceiveSlotIndex })?
                    .balanceUSDT ?? cached
                playWalletStyleBalanceAnimation(
                    displayed: heroDisplayed,
                    chain: heroChain,
                    walletID: id
                )
            } else if usesFocusedSlotHeroBalance {
                syncDisplayedBalanceWithFocusedSlot(animated: false)
            } else {
                usdtBalance = cached
            }
        } else {
            isBalanceStale = true
            if walletChanged {
                let heroDisplayed = resolvedFocusedSlotBalance() ?? 0
                playWalletStyleBalanceAnimation(
                    displayed: heroDisplayed,
                    chain: 0,
                    walletID: id
                )
            } else if usesFocusedSlotHeroBalance {
                syncDisplayedBalanceWithFocusedSlot(animated: false)
            } else {
                usdtBalance = 0
            }
        }
    }

    func purgeWalletCache(id: String) {
        chainBalanceByWalletID.removeValue(forKey: id)
        balanceByWalletID.removeValue(forKey: id)
        fullTransactionsByWalletID.removeValue(forKey: id)
        slotTransactionsByWalletID.keys
            .filter { $0.hasPrefix("\(id):") }
            .forEach { slotTransactionsByWalletID.removeValue(forKey: $0) }
        slotBalanceCacheByWalletID.removeValue(forKey: id)
        heroBalanceTextCacheByWalletID.removeValue(forKey: id)
        UserDefaults.standard.removeObject(forKey: Self.balanceCachePrefix + id)
    }

    /// Pull-to-refresh — balances and history; awaits network before `refreshable` ends.
    func pullToRefresh(transactionLimit: Int = 24) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        loadError = nil
        isHistoryLoading = true
        isPullRefreshing = true
        isBalanceStale = true
        defer {
            if generation == refreshGeneration {
                if transactions.isEmpty {
                    applyDisplayedTransactionsForFocusedSlot()
                }
                isHistoryLoading = false
                isPullRefreshing = false
                scheduleBalanceStaleClear(generation: generation)
            }
        }

        let address: String
        do {
            address = try resolveAddress()
            guard generation == refreshGeneration else { return }
            walletAddress = address
        } catch {
            guard generation == refreshGeneration else { return }
            guard !error.isTransientCancellation else { return }
            loadError = error.localizedDescription
            return
        }

        let activeWalletID = MeshWalletRegistry.activeWalletID
        let needsRestoreDiscovery = activeWalletID.map {
            MeshPrivacyStore.needsFullAddressDiscovery(walletID: $0)
        } ?? false

        MeshBackgroundSendService.shared.restoreForActiveWallet()
        MeshBackgroundSendService.shared.releaseOrphanPendingHolds()

        async let feeStatusTask = MeshBackgroundSendService.shared.refreshFeeStatus()
        async let balanceTask = fetchAggregatedUSDTBalance(
            mainAddress: address,
            walletID: activeWalletID,
            skipRestoreDiscovery: needsRestoreDiscovery,
            fetchMode: .full
        )

        let historyResult: Result<[TronUSDTTransaction], Error>
        do {
            let history = try await fetchInitialWalletHistory(limit: transactionLimit)
            historyResult = .success(history)
        } catch {
            historyResult = .failure(error)
        }

        if let balance = await balanceTask {
            guard generation == refreshGeneration else { return }
            let walletID = MeshWalletRegistry.activeWalletID
            let hold = walletID.map {
                MeshBackgroundSendService.shared.pendingBalanceHold(for: $0, chainBalance: balance.chain)
            } ?? 0
            let mainDisplayed = max(0, balance.chain - hold)
            playWalletStyleBalanceAnimation(
                displayed: mainDisplayed,
                chain: balance.chain,
                walletID: walletID
            )
        } else if generation == refreshGeneration {
            let walletID = activeWalletID
            let chain = walletID.flatMap { chainBalanceByWalletID[$0] } ?? usdtBalance
            playWalletStyleBalanceAnimation(
                displayed: usdtBalance,
                chain: chain,
                walletID: walletID
            )
        }

        switch historyResult {
        case .success(let history):
            guard generation == refreshGeneration else { return }
            await applyLoadedHistory(
                history: history,
                address: address,
                activeWalletID: activeWalletID,
                needsRestoreDiscovery: needsRestoreDiscovery,
                generation: generation,
                forSlot: hdFocusedSlotIndex(walletID: activeWalletID)
            )
        case .failure(let error):
            guard generation == refreshGeneration else { return }
            guard !error.isTransientCancellation else { return }
            applyDisplayedTransactionsForFocusedSlot()
            loadError = error.localizedDescription
        }

        _ = await feeStatusTask
    }

    func load(transactionLimit: Int = 24) async {
        allowsBackgroundPreload = false
        refreshGeneration += 1
        let generation = refreshGeneration

        let walletID = MeshWalletRegistry.activeWalletID
        let hadCachedBalance = walletID.flatMap { walletID in
            chainBalanceByWalletID[walletID] != nil || balanceByWalletID[walletID] != nil
        } ?? false
        let hadCachedTransactions = walletID.flatMap {
            slotTransactionsByWalletID[slotHistoryCacheKey(
                walletID: $0,
                slotIndex: focusedReceiveSlotIndex
            )]
        }?.isEmpty == false

        isLoading = !hadCachedTransactions
        isHistoryLoading = !hadCachedTransactions
        isBalanceLoading = !hadCachedBalance
        if !hadCachedBalance {
            isBalanceStale = true
        }
        loadError = nil

        func finishBalanceSpinner() {
            guard generation == refreshGeneration else { return }
            isBalanceLoading = false
        }

        let address: String
        do {
            address = try resolveAddress()
            guard generation == refreshGeneration else { return }
            walletAddress = address
        } catch {
            guard generation == refreshGeneration else { return }
            guard !error.isTransientCancellation else { return }
            loadError = error.localizedDescription
            return
        }

        let activeWalletID = MeshWalletRegistry.activeWalletID
        let needsRestoreDiscovery = activeWalletID.map {
            MeshPrivacyStore.needsFullAddressDiscovery(walletID: $0)
        } ?? false

        MeshBackgroundSendService.shared.restoreForActiveWallet()
        MeshBackgroundSendService.shared.releaseOrphanPendingHolds()

        if let balance = await fetchAggregatedUSDTBalance(
            mainAddress: address,
            walletID: activeWalletID,
            skipRestoreDiscovery: needsRestoreDiscovery,
            fetchMode: .light
        ) {
            guard generation == refreshGeneration else { return }
            let walletID = MeshWalletRegistry.activeWalletID
            let animateBalanceApply = shouldAnimateNextBalanceApply
            applyDisplayedBalance(
                chain: balance.chain,
                walletID: walletID,
                animated: animateBalanceApply,
                isCompleteRead: balance.isCompleteRead
            )
            shouldAnimateNextBalanceApply = false
            isBalanceStale = false
        } else if generation == refreshGeneration {
            isBalanceStale = false
        }
        finishBalanceSpinner()

        async let feeStatusTask = MeshBackgroundSendService.shared.refreshFeeStatus()

        do {
            let history = try await fetchInitialWalletHistory(limit: transactionLimit)
            guard generation == refreshGeneration else { return }
            await applyLoadedHistory(
                history: history,
                address: address,
                activeWalletID: activeWalletID,
                needsRestoreDiscovery: needsRestoreDiscovery,
                generation: generation,
                forSlot: hdFocusedSlotIndex(walletID: activeWalletID)
            )
        } catch {
            guard generation == refreshGeneration else { return }
            guard !error.isTransientCancellation else { return }
            loadError = error.localizedDescription
        }

        _ = await feeStatusTask

        if generation == refreshGeneration {
            isHistoryLoading = false
            isLoading = false
            shouldAnimateNextBalanceApply = false
            isBalanceStale = false
            allowsBackgroundPreload = true
        }

        if generation == refreshGeneration,
           let walletID = activeWalletID,
           MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        {
            let deferredGeneration = generation
            Task(priority: .utility) { @MainActor in
                await self.preloadVisibleSlotHistoriesInBackground(
                    walletID: walletID,
                    limit: transactionLimit,
                    generation: deferredGeneration
                )
            }
        }
    }

    /// Fast path after unlock: focused receive slot only (HD) or single-address history.
    private func fetchInitialWalletHistory(limit: Int) async throws -> [TronUSDTTransaction] {
        if MeshWalletCredentials.supportsHDWalletFeatures(),
           let walletID = MeshWalletRegistry.activeWalletID
        {
            return try await MeshPrivacyService.fetchActivityHistory(
                limit: limit,
                slotIndex: focusedReceiveSlotIndex,
                walletID: walletID
            )
        }
        return try await fetchFullWalletHistory(limit: limit)
    }

    /// Warms per-slot caches (one Tron address each) without mixing activity across accounts.
    private func preloadVisibleSlotHistoriesInBackground(
        walletID: String,
        limit: Int,
        generation: Int
    ) async {
        let indices = MeshPrivacyStore.visibleReceiveSlotIndices(walletID: walletID)
        for index in indices {
            guard generation == refreshGeneration else { return }
            if index == focusedReceiveSlotIndex,
               slotTransactionsByWalletID[
                   slotHistoryCacheKey(walletID: walletID, slotIndex: index)
               ] != nil
            {
                continue
            }
            do {
                let history = try await MeshPrivacyService.fetchActivityHistory(
                    limit: limit,
                    slotIndex: index,
                    walletID: walletID
                )
                guard generation == refreshGeneration else { return }
                let chain = history.map { WalletTransaction(tron: $0) }
                let merged = mergedHistoryForSlot(
                    chain: chain,
                    slotIndex: index,
                    walletID: walletID,
                    pending: [],
                    address: nil
                )
                slotTransactionsByWalletID[
                    slotHistoryCacheKey(walletID: walletID, slotIndex: index)
                ] = merged
            } catch {
                continue
            }
        }
    }

    private func quickReceiveSlotPlaceholders(walletID: String) -> [WalletReceiveSlotOption] {
        guard let wallet = MeshWalletRegistry.wallet(id: walletID) else { return [] }
        let indices = MeshPrivacyStore.visibleReceiveSlotIndices(walletID: walletID)
        guard !indices.isEmpty else { return [] }

        return indices.map { index in
            return WalletReceiveSlotOption(
                index: index,
                address: index == 0 ? wallet.address : "",
                title: MeshPrivacyStore.receiveSlotDisplayTitle(
                    index: index,
                    walletID: walletID
                ),
                derivationPath: TronWalletService.receiveDerivationPath(accountIndex: index),
                balanceUSDT: slotBalanceCacheByWalletID[walletID]?[index]
            )
        }
    }

    private func hydrateReceiveSlotAddresses(walletID: String) async {
        let preparedID = walletID
        let slots = await Task.detached(priority: .userInitiated) {
            try? await MeshPrivacyService.listWalletReceiveSlotsWithBalances(walletID: walletID)
        }.value
        guard preparedWalletID == preparedID, let slots else { return }
        receiveSlotBalances = mergeSlotBalancesPreservingKnown(
            newSlots: slots,
            walletID: walletID
        )
        syncDisplayedBalanceWithFocusedSlot(animated: false)
    }

    /// Loads all five slot balances; returns on-chain USDT on slot 0 (main).
    @discardableResult
    private func reloadReceiveSlotBalances(walletID: String?) async -> Decimal? {
        guard let walletID,
              MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        else {
            receiveSlotBalances = []
            return nil
        }
        let slots = await Task.detached(priority: .userInitiated) {
            try? await MeshPrivacyService.listWalletReceiveSlotsWithBalances(walletID: walletID)
        }.value
        guard let slots else {
            return receiveSlotBalances.first { $0.index == 0 }?.balanceUSDT
        }
        receiveSlotBalances = mergeSlotBalancesPreservingKnown(
            newSlots: slots,
            walletID: walletID
        )
        return receiveSlotBalances.first { $0.index == 0 }?.balanceUSDT ?? 0
    }

    private func mergeSlotBalancesPreservingKnown(
        newSlots: [WalletReceiveSlotOption],
        walletID: String
    ) -> [WalletReceiveSlotOption] {
        var cache = slotBalanceCacheByWalletID[walletID] ?? [:]
        let merged = newSlots.map { slot -> WalletReceiveSlotOption in
            var copy = slot
            if copy.balanceUSDT == nil,
               let previous = receiveSlotBalances.first(where: { $0.index == slot.index })?.balanceUSDT
            {
                copy.balanceUSDT = previous
            }
            if copy.balanceUSDT == nil, let cached = cache[slot.index] {
                copy.balanceUSDT = cached
            }
            if let balance = copy.balanceUSDT {
                cache[slot.index] = displayAmount(forSlot: slot.index, chain: balance, walletID: walletID)
            }
            return copy
        }
        slotBalanceCacheByWalletID[walletID] = cache
        return merged
    }

    private func hdFocusedSlotIndex(walletID: String?) -> UInt32? {
        guard let walletID,
              MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        else { return nil }
        return focusedReceiveSlotIndex
    }

    private func applyLoadedHistory(
        history: [TronUSDTTransaction],
        address: String,
        activeWalletID: String?,
        needsRestoreDiscovery: Bool,
        generation: Int,
        forSlot slotIndex: UInt32? = nil
    ) async {
        let chain = history.map { WalletTransaction(tron: $0) }
        let sendService = MeshBackgroundSendService.shared
        await sendService.reconcileAfterHistoryLoad(chain: chain)

        if let walletID = MeshWalletRegistry.activeWalletID,
           let slotIndex,
           MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        {
            let slotMerged = mergedHistoryForSlot(
                chain: chain,
                slotIndex: slotIndex,
                walletID: walletID,
                pending: sendService.historyTransactions
            )
            slotTransactionsByWalletID[
                slotHistoryCacheKey(walletID: walletID, slotIndex: slotIndex)
            ] = slotMerged
            syncSelfTransferActivityToPeerSlots(
                chain: chain,
                walletID: walletID,
                sourceSlotIndex: slotIndex,
                pending: sendService.historyTransactions
            )
            if focusedReceiveSlotIndex == slotIndex {
                transactions = slotTransactionsByWalletID[
                    slotHistoryCacheKey(walletID: walletID, slotIndex: slotIndex)
                ] ?? slotMerged
            }
        } else if let walletID = MeshWalletRegistry.activeWalletID {
            let merged = Self.merge(chain: chain, pending: sendService.historyTransactions)
            fullTransactionsByWalletID[walletID] = merged
            transactions = merged
        }

        sendService.pruneTrackedTransfersPresentInChain(chain)
        loadError = nil

        if needsRestoreDiscovery, let walletID = activeWalletID {
            let restoreGeneration = generation
            Task { @MainActor in
                await self.refineBalanceAfterRestore(
                    history: history,
                    mainAddress: address,
                    walletID: walletID,
                    generation: restoreGeneration
                )
            }
        }
    }

    private func refineBalanceAfterRestore(
        history: [TronUSDTTransaction],
        mainAddress: String,
        walletID: String,
        generation: Int
    ) async {
        MeshPrivacyService.registerReceiveIndicesFromActivity(
            transactions: history,
            walletID: walletID
        )
        guard let balance = await fetchAggregatedUSDTBalance(
            mainAddress: mainAddress,
            walletID: walletID,
            skipRestoreDiscovery: false,
            fetchMode: .full
        ) else { return }
        guard generation == refreshGeneration else { return }
        applyDisplayedBalance(
            chain: balance.chain,
            walletID: walletID,
            animated: false,
            isCompleteRead: balance.isCompleteRead
        )
        isBalanceStale = false
    }

    /// Lightweight poll — balance only (used on home screen every few seconds).
    func refreshBalance(showSpinner: Bool = false) async {
        guard WalletSession.hasActiveWallet, !isLoading, !isPullRefreshing else { return }

        if showSpinner { isBalanceLoading = true }
        defer { if showSpinner { isBalanceLoading = false } }

        do {
            let address = try resolveAddress()
            walletAddress = address
            let walletID = MeshWalletRegistry.activeWalletID
            let fetchMode: MeshPrivacyService.BalanceFetchMode = {
                guard let walletID,
                      MeshPrivacyStore.needsFullAddressDiscovery(walletID: walletID)
                else { return .light }
                return .full
            }()
            if let balance = await fetchAggregatedUSDTBalance(
                mainAddress: address,
                walletID: walletID,
                fetchMode: fetchMode
            ) {
                applyDisplayedBalance(
                    chain: balance.chain,
                    walletID: MeshWalletRegistry.activeWalletID,
                    animated: false,
                    isCompleteRead: balance.isCompleteRead
                )
                isBalanceStale = false
                loadError = nil
            }

            if MeshBackgroundSendService.shared.needsHistoryReconcile {
                await MeshBackgroundSendService.shared.refreshWorkerQueuedSendStatuses()
                mergePendingFromBackgroundSend()
            }

        } catch {
            guard !error.isTransientCancellation else { return }
            loadError = error.localizedDescription
        }
    }

    private struct AggregatedUSDTBalance {
        let chain: Decimal
        let isCompleteRead: Bool
    }

    private func fetchAggregatedUSDTBalance(
        mainAddress: String,
        walletID: String?,
        skipRestoreDiscovery: Bool = false,
        fetchMode: MeshPrivacyService.BalanceFetchMode = .full
    ) async -> AggregatedUSDTBalance? {
        _ = skipRestoreDiscovery
        if MeshWalletCredentials.supportsHDWalletFeatures() {
            guard let walletID else { return nil }
            if fetchMode == .light {
                if let balance = await TronAPIService.fetchUSDTBalance(address: mainAddress) {
                    return AggregatedUSDTBalance(
                        chain: Decimal(balance),
                        isCompleteRead: false
                    )
                }
                if let cached = balanceByWalletID[walletID] ?? chainBalanceByWalletID[walletID] {
                    return AggregatedUSDTBalance(chain: cached, isCompleteRead: false)
                }
                return nil
            }
            guard let mainChain = await reloadReceiveSlotBalances(walletID: walletID) else {
                return nil
            }
            let isComplete = !receiveSlotBalances.isEmpty
                && receiveSlotBalances.allSatisfy { $0.balanceUSDT != nil }
            return AggregatedUSDTBalance(chain: mainChain, isCompleteRead: isComplete)
        }
        guard let balance = await TronAPIService.fetchUSDTBalance(address: mainAddress) else {
            return nil
        }
        return AggregatedUSDTBalance(chain: Decimal(balance), isCompleteRead: true)
    }

    private func fetchFullWalletHistory(limit: Int) async throws -> [TronUSDTTransaction] {
        if MeshWalletCredentials.supportsHDWalletFeatures() {
            return try await MeshPrivacyService.fetchActivityHistory(limit: limit)
        }
        let address = try resolveAddress()
        return try await TronUSDTService.fetchTransactions(address: address, limit: limit)
    }

    private func reloadFocusedSlotHistory(
        generation: Int,
        cacheKey: String? = nil
    ) async {
        guard MeshWalletCredentials.supportsHDWalletFeatures(),
              let walletID = MeshWalletRegistry.activeWalletID
        else { return }

        let slotIndex = focusedReceiveSlotIndex
        let cacheKey = cacheKey
            ?? slotHistoryCacheKey(walletID: walletID, slotIndex: slotIndex)

        if slotTransactionsByWalletID[cacheKey] == nil {
            isHistoryLoading = transactions.isEmpty
        }
        defer {
            if generation == refreshGeneration {
                isHistoryLoading = false
            }
        }

        do {
            let history = try await MeshPrivacyService.fetchActivityHistory(
                limit: 24,
                slotIndex: slotIndex,
                walletID: walletID
            )
            guard generation == refreshGeneration,
                  focusedReceiveSlotIndex == slotIndex,
                  walletID == MeshWalletRegistry.activeWalletID
            else { return }

            let chain = history.map { WalletTransaction(tron: $0) }
            let sendService = MeshBackgroundSendService.shared
            await sendService.reconcileAfterHistoryLoad(chain: chain)
            let merged = mergedHistoryForSlot(
                chain: chain,
                slotIndex: slotIndex,
                walletID: walletID,
                pending: sendService.historyTransactions
            )
            slotTransactionsByWalletID[cacheKey] = merged
            syncSelfTransferActivityToPeerSlots(
                chain: chain,
                walletID: walletID,
                sourceSlotIndex: slotIndex,
                pending: sendService.historyTransactions
            )
            transactions = slotTransactionsByWalletID[cacheKey] ?? merged
            loadError = nil
        } catch {
            guard generation == refreshGeneration else { return }
            guard !error.isTransientCancellation else { return }
            applyDisplayedTransactionsForFocusedSlot()
            if transactions.isEmpty {
                loadError = error.localizedDescription
            }
        }
    }

    private func applyDisplayedTransactionsForFocusedSlot() {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return }
        let cacheKey = slotHistoryCacheKey(
            walletID: walletID,
            slotIndex: focusedReceiveSlotIndex
        )

        guard MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID) else {
            transactions = fullTransactionsByWalletID[walletID] ?? []
            return
        }

        guard focusedSlotAddress() != nil else {
            guard !isRefreshingHistory else { return }
            transactions = []
            slotTransactionsByWalletID.removeValue(forKey: cacheKey)
            return
        }

        if let cached = slotTransactionsByWalletID[cacheKey] {
            transactions = cached
            return
        }

        guard !isRefreshingHistory else { return }
        transactions = []
    }

    private var isRefreshingHistory: Bool {
        isPullRefreshing || isHistoryLoading || isLoading
    }

    private func confirmedTransactionsForSlot(
        walletID: String,
        slotIndex: UInt32
    ) -> [WalletTransaction] {
        let cacheKey = slotHistoryCacheKey(walletID: walletID, slotIndex: slotIndex)
        let source: [WalletTransaction]
        if let cached = slotTransactionsByWalletID[cacheKey], !cached.isEmpty {
            source = cached
        } else if slotIndex == focusedReceiveSlotIndex, !transactions.isEmpty {
            source = transactions
        } else {
            source = []
        }
        return source.filter { tx in
            if case .confirmed = tx.transferStatus { return true }
            return false
        }
    }

    private func focusedSlotAddress() -> String? {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return nil }
        return receiveAddress(for: focusedReceiveSlotIndex, walletID: walletID)
    }

    private func receiveAddress(for slotIndex: UInt32, walletID: String) -> String? {
        let trimmed = receiveSlotBalances
            .first(where: { $0.index == slotIndex })?
            .address
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        if slotIndex == 0,
           let main = MeshWalletRegistry.wallet(id: walletID)?.address
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !main.isEmpty
        {
            return main
        }
        return nil
    }

    private func mergedHistoryForSlot(
        chain: [WalletTransaction],
        slotIndex: UInt32,
        walletID: String,
        pending: [WalletTransaction],
        address: String? = nil
    ) -> [WalletTransaction] {
        let resolved = address ?? receiveAddress(for: slotIndex, walletID: walletID)
        guard let resolved, !resolved.isEmpty else { return [] }
        // Chain is fetched for this address; pending rows include sends from and receives to this slot.
        let filteredChain = Self.cullInboundMirrorSends(
            in: Self.chainTransactions(for: chain, slotAddress: resolved),
            account: resolved
        )
        let filteredPending = Self.pendingActivityForSlot(pending, slotAddress: resolved)
        let oriented = Self.merge(chain: filteredChain, pending: filteredPending)
            .compactMap { tx in
                tx.oriented(forAccount: resolved) ?? tx
            }
        return Self.dedupeActivityForAccount(oriented, account: resolved)
    }

    private static func chainTransactions(
        for chain: [WalletTransaction],
        slotAddress: String
    ) -> [WalletTransaction] {
        chain.filter { tx in
            TronAddressCodec.matches(tx.fromAddress, slotAddress)
                || TronAddressCodec.matches(tx.toAddress, slotAddress)
        }
    }

    /// In-flight rows for this receive account. Incoming self-transfers appear only after broadcast.
    private static func pendingActivityForSlot(
        _ pending: [WalletTransaction],
        slotAddress: String
    ) -> [WalletTransaction] {
        pending.compactMap { tx in
            let fromHere = TronAddressCodec.matches(tx.fromAddress, slotAddress)
            let toHere = TronAddressCodec.matches(tx.toAddress, slotAddress)
            guard fromHere || toHere else { return nil }

            if fromHere {
                return tx.oriented(forAccount: slotAddress) ?? tx
            }

            guard toHere else { return nil }
            switch tx.transferStatus {
            case .failed:
                return nil
            case .processing:
                let txID = tx.txID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard TronUSDTService.isPlausibleTronTransactionID(txID) else { return nil }
                return tx.oriented(forAccount: slotAddress) ?? tx
            case .confirmed:
                return tx.oriented(forAccount: slotAddress) ?? tx
            }
        }
    }

    private func slotIndexMatchingAddress(_ address: String, walletID: String) -> UInt32? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for index in MeshPrivacyStore.visibleReceiveSlotIndices(walletID: walletID) {
            guard let slotAddress = receiveAddress(for: index, walletID: walletID),
                  TronAddressCodec.matches(slotAddress, trimmed)
            else { continue }
            return index
        }
        return nil
    }

    private func slotIndicesInvolvingPending(
        _ pending: [WalletTransaction],
        walletID: String
    ) -> Set<UInt32> {
        var indices: Set<UInt32> = [focusedReceiveSlotIndex]
        for tx in pending {
            if let fromIndex = slotIndexMatchingAddress(tx.fromAddress, walletID: walletID) {
                indices.insert(fromIndex)
            }
            if let toIndex = slotIndexMatchingAddress(tx.toAddress, walletID: walletID) {
                indices.insert(toIndex)
            }
        }
        return indices
    }

    /// Mirror txs from one slot's chain load into other visible slot caches (HD self-transfers).
    private func syncSelfTransferActivityToPeerSlots(
        chain: [WalletTransaction],
        walletID: String,
        sourceSlotIndex: UInt32,
        pending: [WalletTransaction]
    ) {
        let visible = MeshPrivacyStore.visibleReceiveSlotIndices(walletID: walletID)
        for tx in chain {
            for index in visible where index != sourceSlotIndex {
                guard let address = receiveAddress(for: index, walletID: walletID),
                      !address.isEmpty,
                      TronAddressCodec.matches(tx.fromAddress, address)
                        || TronAddressCodec.matches(tx.toAddress, address)
                else { continue }
                mergeChainTransactionIntoSlotCache(
                    tx: tx,
                    slotIndex: index,
                    walletID: walletID,
                    address: address,
                    pending: pending
                )
            }
        }
    }

    private func mergeChainTransactionIntoSlotCache(
        tx: WalletTransaction,
        slotIndex: UInt32,
        walletID: String,
        address: String,
        pending: [WalletTransaction]
    ) {
        guard let oriented = tx.oriented(forAccount: address) else { return }
        let cacheKey = slotHistoryCacheKey(walletID: walletID, slotIndex: slotIndex)
        let confirmedChain = (slotTransactionsByWalletID[cacheKey] ?? []).filter { item in
            if case .confirmed = item.transferStatus { return true }
            return false
        }
        if !oriented.txID.isEmpty, confirmedChain.contains(where: { $0.txID == oriented.txID }) {
            return
        }
        if Self.shouldDropMirrorOfInbound(oriented, existing: confirmedChain, account: address) {
            return
        }
        var augmented = confirmedChain
        augmented.append(oriented)
        augmented.sort { $0.timestamp > $1.timestamp }
        slotTransactionsByWalletID[cacheKey] = mergedHistoryForSlot(
            chain: augmented,
            slotIndex: slotIndex,
            walletID: walletID,
            pending: pending,
            address: address
        )
    }

    private func invalidateSlotHistoryCaches(walletID: String) {
        for key in slotTransactionsByWalletID.keys where key.hasPrefix("\(walletID):") {
            slotTransactionsByWalletID.removeValue(forKey: key)
        }
    }

    private func slotHistoryCacheKey(walletID: String, slotIndex: UInt32) -> String {
        "\(walletID):\(slotIndex)"
    }

    private static func addressesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private func resolveAddress() throws -> String {
        guard WalletSession.hasActiveWallet else {
            throw TronAPIError.broadcastFailed("Wallet is not initialized")
        }
        if let id = MeshWalletRegistry.activeWalletID,
           let wallet = MeshWalletRegistry.wallet(id: id),
           !wallet.address.isEmpty {
            return wallet.address
        }
        if let cached = WalletSession.cachedAddress(), !cached.isEmpty {
            return cached
        }
        return try TronUSDTService.currentAddress()
    }

    func mergePendingFromBackgroundSend() {
        guard !isPullRefreshing else { return }
        guard let walletID = MeshWalletRegistry.activeWalletID,
              MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        else {
            applyDisplayedTransactionsForFocusedSlot()
            refreshDisplayedBalanceFromPendingSends()
            return
        }

        let pending = MeshBackgroundSendService.shared.historyTransactions
        for index in slotIndicesInvolvingPending(pending, walletID: walletID) {
            guard let address = receiveAddress(for: index, walletID: walletID) else { continue }
            let cacheKey = slotHistoryCacheKey(walletID: walletID, slotIndex: index)
            let confirmedChain = confirmedTransactionsForSlot(
                walletID: walletID,
                slotIndex: index
            )
            slotTransactionsByWalletID[cacheKey] = mergedHistoryForSlot(
                chain: confirmedChain,
                slotIndex: index,
                walletID: walletID,
                pending: pending,
                address: address
            )
        }

        applyDisplayedTransactionsForFocusedSlot()
        refreshDisplayedBalanceFromPendingSends()
        syncDisplayedBalanceWithFocusedSlot(animated: false)
    }

    /// Disk cache immediately; then network preload for every wallet in the background.
    func preloadAllWalletBalances() {
        guard allowsBackgroundPreload else { return }
        for wallet in MeshWalletRegistry.wallets {
            if chainBalanceByWalletID[wallet.id] == nil,
               let disk = Self.cachedBalanceFromDisk(walletID: wallet.id)
            {
                balanceByWalletID[wallet.id] = disk
            }
        }

        if backgroundPreloadTask != nil { return }
        backgroundPreloadTask = Task(priority: .utility) { @MainActor in
            await preloadAllWalletsFromNetwork()
            backgroundPreloadTask = nil
        }
    }

    /// Preload a single wallet (e.g. after add/import) without waiting for the full sweep.
    func preloadWalletInBackground(walletID: String) {
        Task(priority: .utility) { @MainActor in
            await preloadWalletData(walletID: walletID, historyLimit: 16)
        }
    }

    private func preloadAllWalletsFromNetwork() async {
        for wallet in MeshWalletRegistry.wallets {
            if Task.isCancelled { return }
            await preloadWalletData(walletID: wallet.id, historyLimit: 16)
        }
    }

    private func preloadWalletData(walletID: String, historyLimit: Int) async {
        let needsBalance = chainBalanceByWalletID[walletID] == nil
        let isHD = MeshWalletCredentials.supportsHDWalletFeatures(walletID: walletID)
        let needsHistory: Bool = {
            if isHD {
                return MeshPrivacyStore.visibleReceiveSlotIndices(walletID: walletID)
                    .contains { index in
                        slotTransactionsByWalletID[
                            slotHistoryCacheKey(walletID: walletID, slotIndex: index)
                        ] == nil
                    }
            }
            return fullTransactionsByWalletID[walletID]?.isEmpty != false
        }()
        guard needsBalance || needsHistory else { return }

        let mainAddress = MeshWalletRegistry.wallet(id: walletID)?.address ?? ""
        async let balanceTask: AggregatedUSDTBalance? = needsBalance
            ? fetchAggregatedUSDTBalance(
                mainAddress: mainAddress,
                walletID: walletID,
                fetchMode: .light
            )
            : nil
        async let legacyHistoryTask: [TronUSDTTransaction]? = needsHistory && !isHD
            ? (try? await MeshPrivacyService.fetchActivityHistory(
                limit: historyLimit,
                walletID: walletID
              ))
            : nil

        if let balance = await balanceTask {
            let hold = MeshBackgroundSendService.shared.pendingBalanceHold(
                for: walletID,
                chainBalance: balance.chain
            )
            let displayed = max(0, balance.chain - hold)
            chainBalanceByWalletID[walletID] = balance.chain
            balanceByWalletID[walletID] = displayed
            UserDefaults.standard.set(
                NSDecimalNumber(decimal: displayed).stringValue,
                forKey: Self.balanceCachePrefix + walletID
            )
        }

        if isHD, needsHistory {
            let indices = MeshPrivacyStore.visibleReceiveSlotIndices(walletID: walletID)
            for index in indices {
                guard slotTransactionsByWalletID[
                    slotHistoryCacheKey(walletID: walletID, slotIndex: index)
                ] == nil else { continue }
                guard let slotHistory = try? await MeshPrivacyService.fetchActivityHistory(
                    limit: historyLimit,
                    slotIndex: index,
                    walletID: walletID
                ) else { continue }
                let chain = slotHistory.map { WalletTransaction(tron: $0) }
                slotTransactionsByWalletID[
                    slotHistoryCacheKey(walletID: walletID, slotIndex: index)
                ] = mergedHistoryForSlot(
                    chain: chain,
                    slotIndex: index,
                    walletID: walletID,
                    pending: [],
                    address: nil
                )
            }
        } else if let history = await legacyHistoryTask {
            let chain = history.map { WalletTransaction(tron: $0) }
            fullTransactionsByWalletID[walletID] = Self.merge(
                chain: chain,
                pending: MeshBackgroundSendService.shared.historyTransactions
            )
        }

        applyPreloadedDataToActiveWalletIfNeeded(walletID: walletID)
    }

    private func applyPreloadedDataToActiveWalletIfNeeded(walletID: String) {
        guard walletID == MeshWalletRegistry.activeWalletID,
              preparedWalletID == walletID
        else { return }

        if let chain = chainBalanceByWalletID[walletID] {
            applyDisplayedBalance(
                chain: chain,
                walletID: walletID,
                animated: false,
                isCompleteRead: true
            )
            isBalanceStale = false
            isBalanceLoading = false
        }

        applyDisplayedTransactionsForFocusedSlot()
        if !transactions.isEmpty {
            isHistoryLoading = false
            isLoading = false
        }
    }

    /// Re-applies pending-send holds after background send state changes (no new TronGrid call).
    func refreshDisplayedBalanceFromPendingSends() {
        let sendService = MeshBackgroundSendService.shared
        if !sendService.isHandoffRunning {
            sendService.releaseOrphanPendingHolds()
        }
        guard let walletID = MeshWalletRegistry.activeWalletID,
              let chain = chainBalanceByWalletID[walletID]
        else { return }
        refreshSlotDisplayedBalanceCaches(walletID: walletID)
        applyDisplayedBalance(chain: chain, walletID: walletID, animated: false, isCompleteRead: true)
    }

    private func refreshSlotDisplayedBalanceCaches(walletID: String) {
        var cache = slotBalanceCacheByWalletID[walletID] ?? [:]
        for slot in receiveSlotBalances {
            guard let chain = slot.balanceUSDT else { continue }
            cache[slot.index] = displayAmount(forSlot: slot.index, chain: chain, walletID: walletID)
        }
        slotBalanceCacheByWalletID[walletID] = cache
    }

    private static func cachedBalanceFromDisk(walletID: String) -> Decimal? {
        guard let raw = UserDefaults.standard.string(forKey: balanceCachePrefix + walletID),
              let value = Decimal(string: raw)
        else { return nil }
        return value
    }

    private func applyDisplayedBalance(
        chain: Decimal,
        walletID: String?,
        animated: Bool,
        isCompleteRead: Bool = true,
        forcePresentation: Bool = false
    ) {
        _ = isCompleteRead
        if let walletID {
            recordMainChainBalance(chain: chain, walletID: walletID)
        }

        if usesFocusedSlotHeroBalance {
            syncDisplayedBalanceWithFocusedSlot(animated: animated || forcePresentation)
            return
        }

        let hold = walletID.map {
            MeshBackgroundSendService.shared.pendingBalanceHold(for: $0, chainBalance: chain)
        } ?? 0
        let displayed = max(0, chain - hold)
        let previousChain = walletID.flatMap { chainBalanceByWalletID[$0] }
        let displayChanged = usdtBalance != displayed
        let chainChanged = previousChain != chain
        guard displayChanged || chainChanged || forcePresentation else { return }

        presentHeroBalance(
            displayed: displayed,
            chain: chain,
            animated: animated,
            forcePresentation: forcePresentation
        )
    }

    /// Settle wave + spring digit roll — shared by wallet switch and pull-to-refresh.
    private func playWalletStyleBalanceAnimation(
        displayed: Decimal,
        chain: Decimal,
        walletID: String?
    ) {
        playBalanceUpdateAnimation(restart: true)

        let applyMetadata = { [self] in
            usdtBalance = displayed
            if let walletID, focusedReceiveSlotIndex == 0 {
                recordMainChainBalance(chain: chain, walletID: walletID)
            }
        }

        if heroUsesSlotBalanceSource,
           let slotChain = receiveSlotBalances.first(where: { $0.index == focusedReceiveSlotIndex })?
               .balanceUSDT
        {
            animateFocusedSlotBalanceRoll(
                chain: slotChain,
                walletID: walletID,
                finalize: applyMetadata
            )
        } else if usdtBalance == displayed {
            animateBalanceNumericRoll(to: displayed, finalize: applyMetadata)
        } else {
            animateBalance(applyMetadata)
        }
    }

    /// Hero reads slot balance when the focused card already has a loaded value.
    private var heroUsesSlotBalanceSource: Bool {
        receiveSlotBalances.contains {
            $0.index == focusedReceiveSlotIndex && $0.balanceUSDT != nil
        }
    }

    private func mutateFocusedSlotBalance(
        chain: Decimal,
        animated: Bool,
        walletID: String?
    ) {
        let slotIndex = focusedReceiveSlotIndex
        guard let slotIdx = receiveSlotBalances.firstIndex(where: { $0.index == slotIndex }) else { return }

        var slots = receiveSlotBalances
        var slot = slots[slotIdx]
        slot.balanceUSDT = chain
        slots[slotIdx] = slot

        if let walletID {
            let displayed = displayAmount(forSlot: slotIndex, chain: chain, walletID: walletID)
            slotBalanceCacheByWalletID[walletID, default: [:]][slotIndex] = displayed
        }

        if animated {
            withAnimation(MeshBalanceRevealAnimation.valueChange) {
                receiveSlotBalances = slots
            }
        } else {
            receiveSlotBalances = slots
        }
    }

    private func animateFocusedSlotBalanceRoll(
        chain targetChain: Decimal,
        walletID: String?,
        finalize: @escaping () -> Void
    ) {
        let nudgeChain = targetChain + Self.balanceNumericNudgeDelta
        mutateFocusedSlotBalance(chain: nudgeChain, animated: true, walletID: walletID)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            mutateFocusedSlotBalance(chain: targetChain, animated: true, walletID: walletID)
            withAnimation(MeshBalanceRevealAnimation.valueChange) {
                finalize()
            }
        }
    }

    private func scheduleBalanceStaleClear(generation: Int) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard generation == refreshGeneration else { return }
            isBalanceStale = false
        }
    }

    static func merge(chain: [WalletTransaction], pending: [WalletTransaction]) -> [WalletTransaction] {
        let dedupedChain = dedupeChainTransactions(chain)
        let chainTxIDs = Set(dedupedChain.map(\.txID).filter { !$0.isEmpty })
        let filteredPending = pending.filter { item in
            if pendingSupersededByChain(item, chain: dedupedChain) { return false }
            guard !item.txID.isEmpty else { return true }
            return !chainTxIDs.contains(item.txID)
        }
        let dedupedPending = dedupeActivityPending(filteredPending)

        var byTxID: [String: WalletTransaction] = [:]
        var withoutTxID: [WalletTransaction] = []
        for item in dedupedPending {
            let txID = item.txID.trimmingCharacters(in: .whitespacesAndNewlines)
            if txID.isEmpty {
                withoutTxID.append(item)
            } else {
                byTxID[txID] = item
            }
        }
        for item in dedupedChain {
            let txID = item.txID.trimmingCharacters(in: .whitespacesAndNewlines)
            if txID.isEmpty {
                withoutTxID.append(item)
            } else {
                byTxID[txID] = item
            }
        }

        let withoutTxIDDeduped = dedupeTransactionsWithoutTxID(withoutTxID)
        let merged = (withoutTxIDDeduped + Array(byTxID.values))
            .sorted { $0.timestamp > $1.timestamp }
        return cullInboundMirrorSends(in: merged, account: nil)
    }

    /// One logical transfer per account — drop spurious Sent beside Received on inbound credits.
    static func dedupeActivityForAccount(
        _ items: [WalletTransaction],
        account: String
    ) -> [WalletTransaction] {
        let culled = cullInboundMirrorSends(in: items, account: account)
        var byTxID: [String: WalletTransaction] = [:]
        var withoutTxID: [WalletTransaction] = []

        for item in culled {
            let txID = item.txID.trimmingCharacters(in: .whitespacesAndNewlines)
            if txID.isEmpty {
                withoutTxID.append(item)
                continue
            }
            if let existing = byTxID[txID] {
                byTxID[txID] = preferredActivityTransaction(existing, item, account: account)
            } else {
                byTxID[txID] = item
            }
        }

        var combined = Array(byTxID.values)
        for item in withoutTxID {
            if shouldDropMirrorOfInbound(item, existing: combined, account: account) {
                continue
            }
            combined.append(item)
        }
        return dedupeDuplicateConfirmedSends(
            combined.sorted { $0.timestamp > $1.timestamp },
            account: account
        )
    }

    /// One confirmed outbound row per recipient+amount within a short window (retry / double broadcast).
    static func dedupeDuplicateConfirmedSends(
        _ items: [WalletTransaction],
        account: String
    ) -> [WalletTransaction] {
        let tolerance = Decimal(string: "0.000001") ?? 0
        var kept: [WalletTransaction] = []

        for item in items {
            guard item.kind == .sent,
                  case .confirmed = item.transferStatus,
                  TronAddressCodec.matches(item.fromAddress, account)
            else {
                kept.append(item)
                continue
            }

            if let duplicateIndex = kept.firstIndex(where: { existing in
                guard existing.kind == .sent,
                      case .confirmed = existing.transferStatus,
                      TronAddressCodec.matches(existing.fromAddress, account)
                else { return false }
                guard TronAddressCodec.matches(existing.toAddress, item.toAddress) else { return false }
                let delta = existing.amountUSDT - item.amountUSDT
                guard delta >= -tolerance, delta <= tolerance else { return false }
                return abs(existing.timestamp.timeIntervalSince(item.timestamp)) < 30 * 60
            }) {
                let existing = kept[duplicateIndex]
                let preferred = preferredDuplicateConfirmedSend(existing, item)
                if preferred.id != existing.id {
                    kept[duplicateIndex] = preferred
                }
                continue
            }

            kept.append(item)
        }

        return kept
    }

    private static func preferredDuplicateConfirmedSend(
        _ lhs: WalletTransaction,
        _ rhs: WalletTransaction
    ) -> WalletTransaction {
        let lhsPlausible = TronUSDTService.isPlausibleTronTransactionID(lhs.txID)
        let rhsPlausible = TronUSDTService.isPlausibleTronTransactionID(rhs.txID)
        if lhsPlausible != rhsPlausible {
            return lhsPlausible ? lhs : rhs
        }
        return lhs.timestamp >= rhs.timestamp ? lhs : rhs
    }

    static func cullInboundMirrorSends(
        in items: [WalletTransaction],
        account: String?
    ) -> [WalletTransaction] {
        items.filter { item in
            guard item.kind == .sent else { return true }
            guard let account, !account.isEmpty else { return true }
            return !shouldDropMirrorOfInbound(item, existing: items, account: account)
        }
    }

    static func shouldDropMirrorOfInbound(
        _ candidate: WalletTransaction,
        existing: [WalletTransaction],
        account: String
    ) -> Bool {
        guard candidate.kind == .sent else { return false }
        let tolerance = Decimal(string: "0.000001") ?? 0
        return existing.contains { other in
            guard other.kind == .received else { return false }
            guard TronAddressCodec.matches(other.toAddress, account) else { return false }
            let delta = other.amountUSDT - candidate.amountUSDT
            guard delta >= -tolerance, delta <= tolerance else { return false }
            guard abs(other.timestamp.timeIntervalSince(candidate.timestamp)) < 900 else { return false }
            if TronAddressCodec.matches(candidate.toAddress, account) {
                return true
            }
            return TronAddressCodec.matches(candidate.fromAddress, other.fromAddress)
                && TronAddressCodec.matches(candidate.toAddress, other.toAddress)
        }
    }

    private static func preferredActivityTransaction(
        _ lhs: WalletTransaction,
        _ rhs: WalletTransaction,
        account: String
    ) -> WalletTransaction {
        let lhsScore = activityDirectionScore(lhs, account: account)
        let rhsScore = activityDirectionScore(rhs, account: account)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        return lhs.timestamp >= rhs.timestamp ? lhs : rhs
    }

    private static func activityDirectionScore(
        _ tx: WalletTransaction,
        account: String
    ) -> Int {
        let fromHere = TronAddressCodec.matches(tx.fromAddress, account)
        let toHere = TronAddressCodec.matches(tx.toAddress, account)
        if toHere, !fromHere, tx.kind == .received { return 3 }
        if fromHere, !toHere, tx.kind == .sent { return 3 }
        if toHere, !fromHere { return 2 }
        if fromHere, !toHere { return 2 }
        return 0
    }

    /// Drop bogus outbound pending rows when Tron already shows the inbound transfer.
    static func pendingSupersededByChain(
        _ pending: WalletTransaction,
        chain: [WalletTransaction]
    ) -> Bool {
        guard pending.kind == .sent else { return false }
        let pendingTxID = pending.txID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pendingTxID.isEmpty,
           chain.contains(where: { $0.txID == pendingTxID })
        {
            return true
        }

        let recipient = pending.toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else { return false }
        let tolerance = Decimal(string: "0.000001") ?? 0

        return chain.contains { chainTx in
            guard chainTx.kind == .received else { return false }
            guard TronAddressCodec.matches(chainTx.toAddress, recipient) else { return false }
            let delta = chainTx.amountUSDT - pending.amountUSDT
            guard delta >= -tolerance, delta <= tolerance else { return false }
            if pendingTxID.isEmpty {
                return abs(chainTx.timestamp.timeIntervalSince(pending.timestamp)) < 900
            }
            return chainTx.txID == pendingTxID
        }
    }

    private static func dedupeChainTransactions(_ chain: [WalletTransaction]) -> [WalletTransaction] {
        var byTxID: [String: WalletTransaction] = [:]
        var withoutTxID: [WalletTransaction] = []
        for item in chain {
            let txID = item.txID.trimmingCharacters(in: .whitespacesAndNewlines)
            if txID.isEmpty {
                withoutTxID.append(item)
            } else if let existing = byTxID[txID] {
                if item.timestamp > existing.timestamp { byTxID[txID] = item }
            } else {
                byTxID[txID] = item
            }
        }
        return dedupeTransactionsWithoutTxID(withoutTxID) + Array(byTxID.values)
    }

    private static func dedupeTransactionsWithoutTxID(_ items: [WalletTransaction]) -> [WalletTransaction] {
        var best: [String: WalletTransaction] = [:]
        for item in items {
            let key = activityPendingDedupeKey(item)
            if let existing = best[key], existing.timestamp >= item.timestamp {
                continue
            }
            best[key] = item
        }
        return Array(best.values)
    }

    /// One Activity row per recipient+amount; processing beats failed; newest wins.
    static func dedupeActivityPending(_ pending: [WalletTransaction]) -> [WalletTransaction] {
        var grouped: [String: [WalletTransaction]] = [:]

        for item in pending {
            let key: String
            let txID = item.txID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !txID.isEmpty {
                key = "tx|\(txID.lowercased())"
            } else {
                key = activityPendingDedupeKey(item)
            }
            grouped[key, default: []].append(item)
        }

        var deduped: [WalletTransaction] = []
        for (_, items) in grouped {
            let processing = items
                .filter(\.isProcessing)
                .max(by: { $0.timestamp < $1.timestamp })
            if let processing {
                deduped.append(processing)
                continue
            }
            if let confirmed = items
                .filter({
                    if case .confirmed = $0.transferStatus { return true }
                    return false
                })
                .max(by: { $0.timestamp < $1.timestamp })
            {
                deduped.append(confirmed)
                continue
            }
            if let failed = items
                .filter({
                    if case .failed = $0.transferStatus { return true }
                    return false
                })
                .max(by: { $0.timestamp < $1.timestamp })
            {
                deduped.append(failed)
            }
        }

        return deduped
    }

    static func activityPendingDedupeKey(_ item: WalletTransaction) -> String {
        let recipient = item.toAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sender = item.fromAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let amount = NSDecimalNumber(decimal: item.amountUSDT).stringValue
        return "\(sender)|\(recipient)|\(amount)"
    }

    private func animateBalance(_ updates: () -> Void) {
        withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
            updates()
        }
    }

    /// Brief ±0.01 nudge so `.numericText` rolls even when the settled value is unchanged.
    private func animateBalanceNumericRoll(to target: Decimal, finalize: @escaping () -> Void) {
        let nudge = target + Self.balanceNumericNudgeDelta
        withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
            usdtBalance = nudge
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                finalize()
            }
        }
    }

    private func persistDisplayedBalanceMetadata(chain: Decimal, walletID: String?) {
        guard let walletID else { return }
        chainBalanceByWalletID[walletID] = chain
        let hold = MeshBackgroundSendService.shared.pendingBalanceHold(
            for: walletID,
            chainBalance: chain
        )
        let displayed = max(0, chain - hold)
        balanceByWalletID[walletID] = displayed
        UserDefaults.standard.set(
            NSDecimalNumber(decimal: displayed).stringValue,
            forKey: Self.balanceCachePrefix + walletID
        )
    }

    private static let balanceNumericNudgeDelta: Decimal = 0.01

    private func playBalanceUpdateAnimation(restart: Bool = false) {
        if balanceSettlePhase != 0, !restart { return }
        withAnimation(.easeOut(duration: 0.3)) {
            balanceSettlePhase = 1
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.spring(response: 0.58, dampingFraction: 0.9)) {
                balanceSettlePhase = 0
            }
        }
    }

    private static let balanceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter
    }()
}
