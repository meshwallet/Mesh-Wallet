import Foundation

extension Notification.Name {
    static let meshActiveWalletDidChange = Notification.Name("mesh.activeWalletDidChange")
    /// Posted when a new derived receive address is allocated — home should re-fetch balances/history.
    static let meshWalletBalancesShouldRefresh = Notification.Name("mesh.walletBalancesShouldRefresh")
}

struct StoredWallet: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let address: String
    let createdAt: Date
    var importKind: WalletImportKind

    init(
        id: String,
        name: String,
        address: String,
        createdAt: Date,
        importKind: WalletImportKind = .mnemonic
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.createdAt = createdAt
        self.importKind = importKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        importKind = try container.decodeIfPresent(WalletImportKind.self, forKey: .importKind) ?? .mnemonic
    }
}

enum MeshWalletRegistry {
    static let deletedWalletIDUserInfoKey = "deletedWalletID"

    private static let walletsKey = "mesh.wallets.list"
    private static let activeWalletIDKey = "mesh.wallets.activeId"
    private static let activatedKey = "mesh.wallet.activated"
    private static let registerLock = NSLock()

    static var wallets: [StoredWallet] {
        loadWallets()
    }

    static var activeWalletID: String? {
        get {
            let id = UserDefaults.standard.string(forKey: activeWalletIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id, !id.isEmpty, loadWallets().contains(where: { $0.id == id }) else {
                return loadWallets().first?.id
            }
            return id
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: activeWalletIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeWalletIDKey)
            }
        }
    }

    static var hasAnyWallet: Bool {
        !loadWallets().isEmpty
    }

    static func wallet(id: String) -> StoredWallet? {
        loadWallets().first { $0.id == id }
    }

    static func wallet(address: String) -> StoredWallet? {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return loadWallets().first { $0.address == normalized }
    }

    static func setActiveWallet(id: String, deletedWalletID: String? = nil) {
        guard loadWallets().contains(where: { $0.id == id }) else { return }
        let previous = UserDefaults.standard.string(forKey: activeWalletIDKey)
        activeWalletID = id
        UserDefaults.standard.set(true, forKey: activatedKey)
        if let wallet = wallet(id: id) {
            UserDefaults.standard.set(wallet.address, forKey: "mesh.wallet.address")
            if wallet.importKind == .mnemonic {
                MeshPrivacyStore.ensureDefaultReceiveSetup(walletID: id)
            }
        }
        if previous != id {
            var userInfo: [AnyHashable: Any]?
            if let deletedWalletID {
                userInfo = [deletedWalletIDUserInfoKey: deletedWalletID]
            }
            NotificationCenter.default.post(
                name: .meshActiveWalletDidChange,
                object: id,
                userInfo: userInfo
            )
        }
    }

    /// Adds a new wallet or activates an existing one with the same address.
    @discardableResult
    static func registerWallet(words: [String], address: String, name: String? = nil) -> String {
        registerWallet(
            address: address,
            name: name,
            importKind: .mnemonic,
            words: words,
            privateKeyHex: nil
        )
    }

    @discardableResult
    static func registerPrivateKeyWallet(privateKeyHex: String, address: String, name: String? = nil) -> String {
        registerWallet(
            address: address,
            name: name,
            importKind: .privateKey,
            words: nil,
            privateKeyHex: privateKeyHex
        )
    }

    @discardableResult
    private static func registerWallet(
        address: String,
        name: String?,
        importKind: WalletImportKind,
        words: [String]?,
        privateKeyHex: String?
    ) -> String {
        registerLock.lock()
        defer { registerLock.unlock() }

        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = wallet(address: normalizedAddress) {
            applyCredentials(
                walletID: existing.id,
                importKind: importKind,
                words: words,
                privateKeyHex: privateKeyHex
            )
            updateImportKind(id: existing.id, kind: importKind)
            if let customName = trimmedCustomName(name) {
                updateWalletName(id: existing.id, name: customName)
            }
            setActiveWallet(id: existing.id)
            return existing.id
        }

        let id = UUID().uuidString
        let displayName = resolvedDisplayName(name, existingCount: loadWallets().count)
        let entry = StoredWallet(
            id: id,
            name: displayName,
            address: normalizedAddress,
            createdAt: Date(),
            importKind: importKind
        )

        applyCredentials(walletID: id, importKind: importKind, words: words, privateKeyHex: privateKeyHex)
        var list = loadWallets()

        if list.contains(where: { $0.address == normalizedAddress }) {
            if let existing = wallet(address: normalizedAddress) {
                setActiveWallet(id: existing.id)
                return existing.id
            }
        }

        if !MeshWalletCreationGate.allowsRegistryInsert(for: normalizedAddress) {
            if let blocked = list.first(where: { $0.address == normalizedAddress }) {
                setActiveWallet(id: blocked.id)
                return blocked.id
            }
            if let activeID = activeWalletID, let active = wallet(id: activeID) {
                setActiveWallet(id: active.id)
                return active.id
            }
            if let first = list.first {
                setActiveWallet(id: first.id)
                return first.id
            }
        }
        list.append(entry)
        saveWallets(list)
        setActiveWallet(id: id)
        MeshPrivacyStore.setDefaultSendMethod(.direct, walletID: id)
        return id
    }

    private static func applyCredentials(
        walletID: String,
        importKind: WalletImportKind,
        words: [String]?,
        privateKeyHex: String?
    ) {
        switch importKind {
        case .mnemonic:
            MeshPrivateKeyStore.clear(walletID: walletID)
            if let words {
                MeshMnemonicStore.saveWords(words, walletID: walletID)
            }
        case .privateKey:
            MeshMnemonicStore.clear(walletID: walletID)
            if let privateKeyHex {
                MeshPrivateKeyStore.saveHex(privateKeyHex, walletID: walletID)
            }
        }
    }

    static func suggestedName(existingCount: Int) -> String {
        existingCount == 0 ? "Main wallet" : "Wallet \(existingCount + 1)"
    }

    static func isWalletNameTaken(_ name: String, excludingWalletID: String? = nil) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return loadWallets().contains { wallet in
            if wallet.id == excludingWalletID { return false }
            return wallet.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    static func uniqueAvailableName(existingCount: Int) -> String {
        var count = existingCount
        while count < existingCount + 100 {
            let candidate = suggestedName(existingCount: count)
            if !isWalletNameTaken(candidate) {
                return candidate
            }
            count += 1
        }
        return "Wallet \(UUID().uuidString.prefix(6))"
    }

    static func resolvedDisplayName(_ name: String?, existingCount: Int) -> String {
        if let customName = trimmedCustomName(name) {
            return customName
        }
        return uniqueAvailableName(existingCount: existingCount)
    }

    private static func updateImportKind(id: String, kind: WalletImportKind) {
        var list = loadWallets()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].importKind = kind
        saveWallets(list)
    }

    @discardableResult
    static func updateWalletName(id: String, name: String) -> Bool {
        guard let customName = trimmedCustomName(name) else { return false }
        guard !isWalletNameTaken(customName, excludingWalletID: id) else { return false }
        var list = loadWallets()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return false }
        list[index].name = customName
        saveWallets(list)
        return true
    }

    private static func trimmedCustomName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(32))
    }

    static func removeWallet(id: String) {
        MeshMnemonicStore.clear(walletID: id)
        MeshPrivateKeyStore.clear(walletID: id)
        MeshPrivacyStore.clearWalletData(walletID: id)
        UserDefaults.standard.removeObject(forKey: "mesh.wallet.balance.cached.\(id)")

        let storedActiveID = UserDefaults.standard.string(forKey: activeWalletIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var list = loadWallets().filter { $0.id != id }
        saveWallets(list)

        if list.isEmpty {
            UserDefaults.standard.removeObject(forKey: activatedKey)
            UserDefaults.standard.removeObject(forKey: activeWalletIDKey)
            UserDefaults.standard.removeObject(forKey: "mesh.wallet.address")
            NotificationCenter.default.post(name: .meshActiveWalletDidChange, object: nil)
            return
        }

        if storedActiveID == id {
            if let next = list.first {
                setActiveWallet(id: next.id, deletedWalletID: id)
            }
            return
        }

        if let storedActiveID,
           !storedActiveID.isEmpty,
           list.contains(where: { $0.id == storedActiveID }),
           let wallet = wallet(id: storedActiveID) {
            UserDefaults.standard.set(wallet.address, forKey: "mesh.wallet.address")
            return
        }

        if let next = list.first {
            setActiveWallet(id: next.id)
        }
    }

    static func replaceWallets(_ wallets: [StoredWallet]) {
        saveWallets(wallets)
    }

    static func removeAllWallets() {
        for wallet in loadWallets() {
            MeshMnemonicStore.clear(walletID: wallet.id)
            MeshPrivateKeyStore.clear(walletID: wallet.id)
        }
        saveWallets([])
        activeWalletID = nil
        UserDefaults.standard.removeObject(forKey: activatedKey)
        UserDefaults.standard.removeObject(forKey: "mesh.wallet.address")
        MeshMnemonicStore.clearLegacy()
    }

    static func migrateLegacySingleWalletIfNeeded() {
        guard loadWallets().isEmpty else { return }
        guard let words = MeshMnemonicStore.loadLegacyWords(),
              Valida.allowedMnemonicWordCounts.contains(words.count)
        else { return }

        #if canImport(WalletCore)
        guard let snapshot = try? TronWalletService.importWallet(
            words: words,
            passphrase: MeshMnemonicStore.loadLegacyPassphrase() ?? ""
        ) else { return }

        let id = WalletAccountStore.mainWalletID
        MeshMnemonicStore.saveWords(words, walletID: id)
        if let passphrase = MeshMnemonicStore.loadLegacyPassphrase() {
            MeshMnemonicStore.savePassphrase(passphrase, walletID: id)
        }
        let entry = StoredWallet(id: id, name: "Main wallet", address: snapshot.address, createdAt: Date())
        saveWallets([entry])
        setActiveWallet(id: id)
        MeshMnemonicStore.clearLegacy()
        #endif
    }

    private static func loadWallets() -> [StoredWallet] {
        guard let data = UserDefaults.standard.data(forKey: walletsKey),
              let decoded = try? JSONDecoder().decode([StoredWallet].self, from: data)
        else { return [] }
        return decoded
    }

    private static func saveWallets(_ wallets: [StoredWallet]) {
        guard let data = try? JSONEncoder().encode(wallets) else { return }
        UserDefaults.standard.set(data, forKey: walletsKey)
    }
}
