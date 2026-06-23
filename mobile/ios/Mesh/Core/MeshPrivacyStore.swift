import Foundation

enum MeshPrivacyStore {
    private static let enabledSuffix = "privateSendEnabled"
    private static let legacyEnabledSuffix = "privateSendReceive"
    private static let nextReceiveIndexSuffix = "nextReceiveIndex"
    private static let registeredIndicesSuffix = "registeredReceiveIndices"
    private static let nextRelayIndexSuffix = "nextRelayIndex"
    private static let privateSendRecipientMaskSuffix = "privateSendRecipientMask"
    private static let sendModeSuffix = "privateSendMode"
    private static let defaultSendMethodSuffix = "defaultSendMethod"
    private static let addressDiscoveryCompleteSuffix = "addressDiscoveryComplete"
    private static let selectedReceiveSlotSuffix = "selectedReceiveSlot"
    private static let selectedSendSlotSuffix = "selectedSendSlot"
    private static let activeReceiveAddressCountSuffix = "activeReceiveAddressCount"
    private static let hiddenReceiveSlotIndicesSuffix = "hiddenReceiveSlotIndices"
    private static let receiveSlotNameSuffix = "receiveSlotName"

    /// Fixed receive addresses per wallet: index 0 (main) + indices 1…4.
    static let walletReceiveSlotCount: UInt32 = 5

    /// Privacy-only deep recovery: 1024 receive addresses (indices 0…1023).
    static let deepRecoveryScanAddressCount: UInt32 = 1024
    static let deepRecoveryScanMaxIndex: UInt32 = deepRecoveryScanAddressCount - 1

    static func walletReceiveSlotIndices() -> [UInt32] {
        Array(0..<walletReceiveSlotCount)
    }

    /// Registers slots 0…4 and caps discovery to this set.
    static func ensureWalletReceiveSlots(walletID: String) {
        for index in walletReceiveSlotIndices() {
            registerReceiveIndex(index, walletID: walletID)
        }
        let key = storageKey(nextReceiveIndexSuffix, walletID: walletID)
        let next = max(UInt32(UserDefaults.standard.integer(forKey: key)), walletReceiveSlotCount)
        UserDefaults.standard.set(Int(next), forKey: key)
        markAddressDiscoveryComplete(walletID: walletID)
    }

    /// Default setup: main address (index 0) only; user adds more from home (up to 5).
    static func ensureDefaultReceiveSetup(walletID: String) {
        registerReceiveIndex(0, walletID: walletID)
        let countKey = storageKey(activeReceiveAddressCountSuffix, walletID: walletID)
        if UserDefaults.standard.object(forKey: countKey) == nil {
            setActiveReceiveAddressCount(1, walletID: walletID)
        }
        let nextKey = storageKey(nextReceiveIndexSuffix, walletID: walletID)
        if UserDefaults.standard.integer(forKey: nextKey) < 1 {
            UserDefaults.standard.set(1, forKey: nextKey)
        }
    }

    static func activeReceiveAddressCount(walletID: String) -> UInt32 {
        ensureDefaultReceiveSetup(walletID: walletID)
        let key = storageKey(activeReceiveAddressCountSuffix, walletID: walletID)
        let stored = UserDefaults.standard.integer(forKey: key)
        return UInt32(max(1, min(stored, Int(walletReceiveSlotCount))))
    }

    static func setActiveReceiveAddressCount(_ count: UInt32, walletID: String) {
        let clamped = min(max(count, 1), walletReceiveSlotCount)
        UserDefaults.standard.set(
            Int(clamped),
            forKey: storageKey(activeReceiveAddressCountSuffix, walletID: walletID)
        )
    }

    /// Indices 0…(count−1) minus user-hidden slots (home / receive / send pickers).
    static func visibleReceiveSlotIndices(walletID: String) -> [UInt32] {
        let count = activeReceiveAddressCount(walletID: walletID)
        let hidden = hiddenReceiveSlotIndices(walletID: walletID)
        return (0..<Int(count))
            .map { UInt32($0) }
            .filter { !hidden.contains($0) }
    }

    static func visibleReceiveAddressCount(walletID: String) -> UInt32 {
        UInt32(visibleReceiveSlotIndices(walletID: walletID).count)
    }

    static func hiddenReceiveSlotIndices(walletID: String) -> Set<UInt32> {
        let key = storageKey(hiddenReceiveSlotIndicesSuffix, walletID: walletID)
        guard let raw = UserDefaults.standard.array(forKey: key) as? [Int] else { return [] }
        return Set(raw.filter { $0 > 0 }.map { UInt32($0) })
    }

    /// Adds the next sequential address (or reuses a previously hidden slot). Returns new index or nil at max (5).
    @discardableResult
    static func addReceiveAddress(walletID: String) -> UInt32? {
        ensureDefaultReceiveSetup(walletID: walletID)
        let current = activeReceiveAddressCount(walletID: walletID)
        var hidden = hiddenReceiveSlotIndices(walletID: walletID)

        if let reused = (1..<Int(current))
            .map({ UInt32($0) })
            .first(where: { hidden.contains($0) })
        {
            hidden.remove(reused)
            setHiddenReceiveSlotIndices(hidden, walletID: walletID)
            registerReceiveIndex(reused, walletID: walletID)
            ensureNextReceiveIndexAbove(reused, walletID: walletID)
            return reused
        }

        guard current < walletReceiveSlotCount else { return nil }
        let newIndex = current
        registerReceiveIndex(newIndex, walletID: walletID)
        setActiveReceiveAddressCount(current + 1, walletID: walletID)
        ensureNextReceiveIndexAbove(newIndex, walletID: walletID)
        return newIndex
    }

    /// Hides a single receive slot. Main (index 0) cannot be removed.
    static func removeReceiveAddress(at index: UInt32, walletID: String) -> Bool {
        guard index > 0 else { return false }
        ensureDefaultReceiveSetup(walletID: walletID)
        let current = activeReceiveAddressCount(walletID: walletID)
        guard index < current else { return false }

        var hidden = hiddenReceiveSlotIndices(walletID: walletID)
        guard !hidden.contains(index) else { return false }
        hidden.insert(index)
        setHiddenReceiveSlotIndices(hidden, walletID: walletID)

        setReceiveSlotCustomName(nil, index: index, walletID: walletID)
        unregisterReceiveIndex(index, walletID: walletID)

        let selected = selectedReceiveSlotIndex(walletID: walletID)
        if selected == index {
            setSelectedWalletSlotIndex(0, walletID: walletID)
        } else if !visibleReceiveSlotIndices(walletID: walletID).contains(selected) {
            setSelectedWalletSlotIndex(0, walletID: walletID)
        }
        return true
    }

    private static func setHiddenReceiveSlotIndices(_ indices: Set<UInt32>, walletID: String) {
        let key = storageKey(hiddenReceiveSlotIndicesSuffix, walletID: walletID)
        if indices.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(indices.sorted().map { Int($0) }, forKey: key)
        }
    }

    private static func unregisterReceiveIndex(_ index: UInt32, walletID: String) {
        var indices = Set(registeredReceiveIndices(walletID: walletID))
        indices.remove(index)
        indices.insert(0)
        let stored = indices.sorted().map { Int($0) }
        UserDefaults.standard.set(
            stored,
            forKey: storageKey(registeredIndicesSuffix, walletID: walletID)
        )
    }

    static func selectedReceiveSlotIndex(walletID: String? = MeshWalletRegistry.activeWalletID) -> UInt32 {
        guard let walletID else { return 0 }
        let visible = visibleReceiveSlotIndices(walletID: walletID)
        guard !visible.isEmpty else { return 0 }
        let stored = UserDefaults.standard.integer(
            forKey: storageKey(selectedReceiveSlotSuffix, walletID: walletID)
        )
        let candidate = UInt32(max(0, stored))
        if visible.contains(candidate) { return candidate }
        return visible.last ?? 0
    }

    static func setSelectedReceiveSlotIndex(_ index: UInt32, walletID: String) {
        let visible = visibleReceiveSlotIndices(walletID: walletID)
        let resolved = visible.contains(index) ? index : (visible.last ?? 0)
        UserDefaults.standard.set(
            Int(resolved),
            forKey: storageKey(selectedReceiveSlotSuffix, walletID: walletID)
        )
    }

    static func selectedSendSlotIndex(walletID: String? = MeshWalletRegistry.activeWalletID) -> UInt32 {
        guard let walletID else { return 0 }
        let visible = visibleReceiveSlotIndices(walletID: walletID)
        guard !visible.isEmpty else { return 0 }
        let stored = UserDefaults.standard.integer(
            forKey: storageKey(selectedSendSlotSuffix, walletID: walletID)
        )
        let candidate = UInt32(max(0, stored))
        if visible.contains(candidate) { return candidate }
        return visible.last ?? 0
    }

    static func setSelectedSendSlotIndex(_ index: UInt32, walletID: String) {
        let visible = visibleReceiveSlotIndices(walletID: walletID)
        let resolved = visible.contains(index) ? index : (visible.last ?? 0)
        UserDefaults.standard.set(
            Int(resolved),
            forKey: storageKey(selectedSendSlotSuffix, walletID: walletID)
        )
    }

    /// Last slot picked on home / receive / send (keeps all three in sync).
    static func selectedWalletSlotIndex(walletID: String? = MeshWalletRegistry.activeWalletID) -> UInt32 {
        selectedReceiveSlotIndex(walletID: walletID)
    }

    static func setSelectedWalletSlotIndex(_ index: UInt32, walletID: String) {
        setSelectedReceiveSlotIndex(index, walletID: walletID)
        setSelectedSendSlotIndex(index, walletID: walletID)
    }

    static func receiveSlotTitle(index: UInt32) -> String {
        receiveSlotDisplayTitle(index: index, walletID: MeshWalletRegistry.activeWalletID)
    }

    static func receiveSlotCustomName(
        index: UInt32,
        walletID: String
    ) -> String? {
        let key = receiveSlotNameKey(index: index, walletID: walletID)
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setReceiveSlotCustomName(
        _ name: String?,
        index: UInt32,
        walletID: String
    ) {
        let key = receiveSlotNameKey(index: index, walletID: walletID)
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            UserDefaults.standard.set(name, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func receiveSlotDisplayTitle(
        index: UInt32,
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) -> String {
        guard let walletID else {
            return fallbackReceiveSlotTitle(index: index)
        }
        if let custom = receiveSlotCustomName(index: index, walletID: walletID) {
            return custom
        }
        return fallbackReceiveSlotTitle(index: index)
    }

    private static func fallbackReceiveSlotTitle(index: UInt32) -> String {
        if index == 0 {
            return L10n.Receive.mainAddress
        }
        return L10n.WalletAddressDrawer.balanceSlot(Int(index + 1))
    }

    private static func receiveSlotNameKey(index: UInt32, walletID: String) -> String {
        storageKey("\(receiveSlotNameSuffix).\(index)", walletID: walletID)
    }

    private static func clearReceiveSlotNames(from index: UInt32, walletID: String) {
        for slotIndex in index..<walletReceiveSlotCount {
            setReceiveSlotCustomName(nil, index: slotIndex, walletID: walletID)
        }
    }

    static func isPrivateSendEnabled(walletID: String? = MeshWalletRegistry.activeWalletID) -> Bool {
        guard let walletID else { return false }
        let key = storageKey(enabledSuffix, walletID: walletID)
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        let legacyKey = storageKey(legacyEnabledSuffix, walletID: walletID)
        if UserDefaults.standard.object(forKey: legacyKey) != nil {
            return UserDefaults.standard.bool(forKey: legacyKey)
        }
        return false
    }

    static func setPrivateSendEnabled(_ enabled: Bool, walletID: String? = MeshWalletRegistry.activeWalletID) {
        guard let walletID else { return }
        UserDefaults.standard.set(enabled, forKey: storageKey(enabledSuffix, walletID: walletID))
    }

    @available(*, deprecated, renamed: "isPrivateSendEnabled")
    static func isPrivateSendReceiveEnabled(walletID: String? = MeshWalletRegistry.activeWalletID) -> Bool {
        isPrivateSendEnabled(walletID: walletID)
    }

    @available(*, deprecated, renamed: "setPrivateSendEnabled")
    static func setPrivateSendReceiveEnabled(_ enabled: Bool, walletID: String? = MeshWalletRegistry.activeWalletID) {
        setPrivateSendEnabled(enabled, walletID: walletID)
    }

    /// Returns the index used for this receive and advances the counter for the next one.
    static func allocateReceiveAccountIndex(walletID: String? = MeshWalletRegistry.activeWalletID) -> UInt32 {
        guard let walletID else { return 1 }
        let key = storageKey(nextReceiveIndexSuffix, walletID: walletID)
        let current = max(UInt32(UserDefaults.standard.integer(forKey: key)), 1)
        UserDefaults.standard.set(Int(current + 1), forKey: key)
        registerReceiveIndex(current, walletID: walletID)
        return current
    }

    static func peekNextReceiveAccountIndex(walletID: String? = MeshWalletRegistry.activeWalletID) -> UInt32 {
        guard let walletID else { return 1 }
        let stored = UserDefaults.standard.integer(forKey: storageKey(nextReceiveIndexSuffix, walletID: walletID))
        return UInt32(max(stored, 1))
    }

    static func registeredReceiveIndices(walletID: String? = MeshWalletRegistry.activeWalletID) -> [UInt32] {
        guard let walletID else { return [0] }
        let key = storageKey(registeredIndicesSuffix, walletID: walletID)
        guard let raw = UserDefaults.standard.array(forKey: key) as? [Int], !raw.isEmpty else {
            return [0]
        }
        var indices = Set<UInt32>([0])
        for value in raw where value >= 0 {
            indices.insert(UInt32(value))
        }
        return indices.sorted()
    }

    /// Visible receive slots (0…count−1) used for balance, history, and send.
    static func monitoredReceiveIndices(walletID: String? = MeshWalletRegistry.activeWalletID) -> [UInt32] {
        guard let walletID else { return [0] }
        return visibleReceiveSlotIndices(walletID: walletID)
    }

    static func registerReceiveIndex(_ index: UInt32, walletID: String) {
        var indices = Set(registeredReceiveIndices(walletID: walletID))
        indices.insert(index)
        let stored = indices.sorted().map { Int($0) }
        UserDefaults.standard.set(stored, forKey: storageKey(registeredIndicesSuffix, walletID: walletID))
    }

    /// Ensures `monitoredReceiveIndices` includes `index` after on-chain funds on a derived address.
    static func ensureNextReceiveIndexAbove(_ index: UInt32, walletID: String) {
        let key = storageKey(nextReceiveIndexSuffix, walletID: walletID)
        let current = max(UInt32(UserDefaults.standard.integer(forKey: key)), 1)
        let needed = index + 1
        if needed > current {
            UserDefaults.standard.set(Int(needed), forKey: key)
        }
    }

    static func privateSendMode(walletID: String? = MeshWalletRegistry.activeWalletID) -> MeshPrivateSendMode {
        guard let walletID else { return .standard }
        let raw = UserDefaults.standard.string(forKey: storageKey(sendModeSuffix, walletID: walletID))
        return MeshPrivateSendMode(rawValue: raw ?? "") ?? .standard
    }

    static func setPrivateSendMode(_ mode: MeshPrivateSendMode, walletID: String? = MeshWalletRegistry.activeWalletID) {
        guard let walletID else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: storageKey(sendModeSuffix, walletID: walletID))
    }

    static func defaultSendMethod(walletID: String? = MeshWalletRegistry.activeWalletID) -> MeshDefaultSendMethod {
        guard let walletID else { return .direct }
        let key = storageKey(defaultSendMethodSuffix, walletID: walletID)
        if let raw = UserDefaults.standard.string(forKey: key),
           let method = MeshDefaultSendMethod(rawValue: raw) {
            return method
        }
        applyDefaultSendMethod(.direct, walletID: walletID)
        UserDefaults.standard.set(MeshDefaultSendMethod.direct.rawValue, forKey: key)
        return .direct
    }

    static func setDefaultSendMethod(
        _ method: MeshDefaultSendMethod,
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) {
        guard let walletID else { return }
        UserDefaults.standard.set(method.rawValue, forKey: storageKey(defaultSendMethodSuffix, walletID: walletID))
        applyDefaultSendMethod(method, walletID: walletID)
    }

    static func applyDefaultSendMethod(
        _ method: MeshDefaultSendMethod,
        walletID: String? = MeshWalletRegistry.activeWalletID
    ) {
        switch method {
        case .direct:
            setPrivateSendEnabled(false, walletID: walletID)
        case .standard:
            setPrivateSendEnabled(true, walletID: walletID)
            setPrivateSendMode(.standard, walletID: walletID)
        }
    }

    static func peekRelayAccountIndex(walletID: String? = MeshWalletRegistry.activeWalletID) -> UInt32 {
        guard let walletID else { return 1 }
        let stored = UserDefaults.standard.integer(forKey: storageKey(nextRelayIndexSuffix, walletID: walletID))
        return UInt32(max(stored, 1))
    }

    /// Fresh intermediate address for separated (relay) sends.
    @discardableResult
    static func allocateRelayAccountIndex(walletID: String? = MeshWalletRegistry.activeWalletID) -> UInt32 {
        guard let walletID else { return 1 }
        let key = storageKey(nextRelayIndexSuffix, walletID: walletID)
        let current = max(UInt32(UserDefaults.standard.integer(forKey: key)), 1)
        UserDefaults.standard.set(Int(current + 1), forKey: key)
        return current
    }

    /// Private-send final recipients — hidden from main-wallet history (chain shows hop to relay only).
    static func recordPrivateSendRecipient(_ address: String, walletID: String? = MeshWalletRegistry.activeWalletID) {
        guard let walletID else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var stored = privateSendRecipientMasks(walletID: walletID)
        stored.insert(trimmed)
        let capped = Array(stored).sorted().suffix(100)
        UserDefaults.standard.set(Array(capped), forKey: storageKey(privateSendRecipientMaskSuffix, walletID: walletID))
    }

    static func privateSendRecipientMasks(walletID: String? = MeshWalletRegistry.activeWalletID) -> Set<String> {
        guard let walletID else { return [] }
        let key = storageKey(privateSendRecipientMaskSuffix, walletID: walletID)
        guard let raw = UserDefaults.standard.stringArray(forKey: key) else { return [] }
        return Set(raw)
    }

    /// Main + derived receive addresses (user-controlled spend/receive), excluding relay wallets.
    static func ownedWalletAddresses(walletID: String? = MeshWalletRegistry.activeWalletID) -> Set<String> {
        guard let walletID else { return [] }
        var addresses = Set<String>()
        if let wallet = MeshWalletRegistry.wallet(id: walletID), !wallet.address.isEmpty {
            addresses.insert(wallet.address)
        }
        guard let words = MeshMnemonicStore.loadWords(walletID: walletID), !words.isEmpty else {
            return addresses
        }
        let passphrase = MeshMnemonicStore.loadPassphrase(walletID: walletID) ?? ""
        for index in monitoredReceiveIndices(walletID: walletID) {
            if let derived = try? TronWalletService.deriveReceiveAddress(
                accountIndex: index,
                words: words,
                passphrase: passphrase
            ) {
                addresses.insert(derived)
            }
        }
        return addresses
    }

    /// True until a full funded-address sweep has completed (e.g. after restore or wallet re-import).
    static func needsFullAddressDiscovery(walletID: String) -> Bool {
        !UserDefaults.standard.bool(
            forKey: storageKey(addressDiscoveryCompleteSuffix, walletID: walletID)
        )
    }

    static func markAddressDiscoveryComplete(walletID: String) {
        UserDefaults.standard.set(true, forKey: storageKey(addressDiscoveryCompleteSuffix, walletID: walletID))
    }

    static func clearWalletData(walletID: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(enabledSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(legacyEnabledSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(nextReceiveIndexSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(registeredIndicesSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(nextRelayIndexSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(privateSendRecipientMaskSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(sendModeSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(defaultSendMethodSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(addressDiscoveryCompleteSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(hiddenReceiveSlotIndicesSuffix, walletID: walletID))
        UserDefaults.standard.removeObject(forKey: storageKey(activeReceiveAddressCountSuffix, walletID: walletID))
        clearReceiveSlotNames(from: 0, walletID: walletID)
    }

    private static func storageKey(_ suffix: String, walletID: String) -> String {
        "mesh.privacy.\(walletID).\(suffix)"
    }
}
