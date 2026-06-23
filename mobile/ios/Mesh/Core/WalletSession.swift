import Foundation

enum WalletSession {
    private static let routingSchemaVersion = 4
    private static let routingSchemaKey = "mesh.routing.schema"
    static let onboardingCompleteKey = "mesh.wallet.onboarding.complete"

    /// Wallet is usable only after the full create/restore + security flow completed.
    static var hasActiveWallet: Bool {
        UserDefaults.standard.bool(forKey: onboardingCompleteKey)
            && MeshWalletRegistry.hasAnyWallet
            && activeDerivedSnapshot() != nil
    }

    static var activeWalletID: String? {
        MeshWalletRegistry.activeWalletID
    }

    static func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: onboardingCompleteKey)
        UserDefaults.standard.set(true, forKey: "mesh.wallet.activated")
    }

    static func reconcile() {
        applyRoutingSchemaUpgradeIfNeeded()
        MeshWalletRegistry.migrateLegacySingleWalletIfNeeded()
        reconcileIncompleteOnboardingState()

        guard hasActiveWallet else {
            if MeshWalletRegistry.hasAnyWallet {
                purgeOrphanRegistryEntries()
            } else {
                resetAllWallets()
            }
            return
        }

        if let wallet = MeshWalletRegistry.wallet(id: MeshWalletRegistry.activeWalletID ?? "") {
            UserDefaults.standard.set(wallet.address, forKey: "mesh.wallet.address")
        }
    }

    static func registerWallet(words: [String], address: String, name: String? = nil) -> String {
        let walletID = MeshWalletRegistry.registerWallet(words: words, address: address, name: name)
        UserDefaults.standard.set(true, forKey: "mesh.wallet.activated")
        if let wallet = MeshWalletRegistry.wallet(id: walletID) {
            UserDefaults.standard.set(wallet.address, forKey: "mesh.wallet.address")
        }
        return walletID
    }

    static func setActiveWallet(id: String) {
        MeshWalletRegistry.setActiveWallet(id: id)
        if let wallet = MeshWalletRegistry.wallet(id: id) {
            UserDefaults.standard.set(wallet.address, forKey: "mesh.wallet.address")
        }
    }

    static func cachedAddress() -> String? {
        guard hasActiveWallet else { return nil }
        if let wallet = MeshWalletRegistry.wallet(id: MeshWalletRegistry.activeWalletID ?? "") {
            return wallet.address
        }
        return try? TronUSDTService.currentAddress()
    }

    static var canRemoveActiveWallet: Bool {
        MeshWalletRegistry.wallets.count > 1
    }

    /// Removes the active wallet and switches to another. Fails if it is the only wallet.
    static func reset() {
        guard canRemoveActiveWallet else { return }
        guard let activeID = MeshWalletRegistry.activeWalletID else {
            resetAllWallets()
            return
        }
        removeWallet(id: activeID)
    }

    /// Removes one wallet. Fails if it is the only wallet on the device.
    static func removeWallet(id: String) {
        guard MeshWalletRegistry.wallets.count > 1 else { return }
        MeshWalletRegistry.removeWallet(id: id)
        guard MeshWalletRegistry.hasAnyWallet else {
            resetAllWallets()
            return
        }
        if let active = MeshWalletRegistry.activeWalletID {
            setActiveWallet(id: active)
        }
    }

    private static func resetAllWallets() {
        MeshWalletRegistry.removeAllWallets()
        MeshPasscodeStore.clear()
        UserDefaults.standard.removeObject(forKey: onboardingCompleteKey)
        UserDefaults.standard.removeObject(forKey: "mesh.wallet.activated")
        purgeLegacyPreferenceKeys()
    }

    /// Drops wallets saved before passcode confirmation (interrupted onboarding).
    private static func reconcileIncompleteOnboardingState() {
        guard MeshWalletRegistry.hasAnyWallet else { return }

        if UserDefaults.standard.bool(forKey: onboardingCompleteKey) {
            return
        }

        // Safety first: never wipe existing wallets on app open due to a missing
        // onboarding flag. This could happen after migrations or UserDefaults drift.
        if hasAnyRecoverableWalletCredentials() {
            markOnboardingComplete()
            return
        }

        if MeshPasscodeStore.isEnabled {
            markOnboardingComplete()
            return
        }
    }

    private static func hasAnyRecoverableWalletCredentials() -> Bool {
        MeshWalletRegistry.wallets.contains { wallet in
            switch wallet.importKind {
            case .mnemonic:
                guard let words = MeshMnemonicStore.loadWords(walletID: wallet.id) else { return false }
                return Valida.allowedMnemonicWordCounts.contains(words.count)
            case .privateKey:
                return MeshPrivateKeyStore.loadHex(walletID: wallet.id) != nil
            }
        }
    }

    private static func purgeOrphanRegistryEntries() {
        let valid = MeshWalletRegistry.wallets.filter { wallet in
            switch wallet.importKind {
            case .mnemonic:
                guard let words = MeshMnemonicStore.loadWords(walletID: wallet.id),
                      Valida.allowedMnemonicWordCounts.contains(words.count)
                else { return false }
                return true
            case .privateKey:
                return MeshPrivateKeyStore.loadHex(walletID: wallet.id) != nil
            }
        }
        if valid.isEmpty {
            resetAllWallets()
        } else {
            MeshWalletRegistry.replaceWallets(valid)
            if let active = MeshWalletRegistry.activeWalletID,
               valid.contains(where: { $0.id == active }) {
                MeshWalletRegistry.setActiveWallet(id: active)
            } else if let first = valid.first {
                MeshWalletRegistry.setActiveWallet(id: first.id)
            }
        }
    }

    private static func applyRoutingSchemaUpgradeIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: routingSchemaKey)
        guard stored < routingSchemaVersion else { return }

        MeshWalletRegistry.migrateLegacySingleWalletIfNeeded()
        UserDefaults.standard.set(routingSchemaVersion, forKey: routingSchemaKey)
    }

    private static func purgeLegacyPreferenceKeys() {
        UserDefaults.standard.removeObject(forKey: "mesh.wallet.configured")
        UserDefaults.standard.removeObject(forKey: "mesh.onboarding.completed")
    }

    private static func activeDerivedSnapshot() -> TronWalletSnapshot? {
        guard let walletID = MeshWalletRegistry.activeWalletID,
              let wallet = MeshWalletRegistry.wallet(id: walletID)
        else { return nil }

        #if canImport(WalletCore)
        switch wallet.importKind {
        case .mnemonic:
            guard let words = MeshMnemonicStore.loadWords(walletID: walletID),
                  Valida.allowedMnemonicWordCounts.contains(words.count)
            else { return nil }
            return try? TronWalletService.importWallet(
                words: words,
                passphrase: MeshMnemonicStore.loadPassphrase(walletID: walletID) ?? ""
            )
        case .privateKey:
            guard let hex = MeshPrivateKeyStore.loadHex(walletID: walletID) else { return nil }
            return try? TronWalletService.importPrivateKey(hex: hex)
        }
        #else
        return nil
        #endif
    }
}
