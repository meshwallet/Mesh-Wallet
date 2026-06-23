import Foundation

enum MeshMnemonicStore {
    private static let legacyMnemonicAccount = "mesh.tron.mnemonic"
    private static let legacyPassphraseAccount = "mesh.tron.passphrase"

    static func mnemonicAccount(walletID: String) -> String {
        "mesh.tron.mnemonic.\(walletID)"
    }

    static func passphraseAccount(walletID: String) -> String {
        "mesh.tron.passphrase.\(walletID)"
    }

    static func saveWords(_ words: [String], walletID: String) {
        let normalized = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let joined = normalized.joined(separator: " ")
        guard let data = joined.data(using: .utf8) else { return }
        guard KeychainService.save(data, account: mnemonicAccount(walletID: walletID)) else {
            assertionFailure("Failed to save mnemonic to Keychain")
            return
        }
    }

    static func loadWords(walletID: String) -> [String]? {
        guard let data = KeychainService.load(account: mnemonicAccount(walletID: walletID)),
              let joined = String(data: data, encoding: .utf8),
              !joined.isEmpty
        else { return nil }
        return joined.split(separator: " ").map(String.init)
    }

    static func savePassphrase(_ passphrase: String, walletID: String) {
        guard let data = passphrase.data(using: .utf8) else { return }
        _ = KeychainService.save(data, account: passphraseAccount(walletID: walletID))
    }

    static func loadPassphrase(walletID: String) -> String? {
        guard let data = KeychainService.load(account: passphraseAccount(walletID: walletID)),
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func clear(walletID: String) {
        _ = KeychainService.delete(account: mnemonicAccount(walletID: walletID))
        _ = KeychainService.delete(account: passphraseAccount(walletID: walletID))
    }

    // MARK: - Legacy single-wallet (migration)

    static func loadLegacyWords() -> [String]? {
        guard let data = KeychainService.load(account: legacyMnemonicAccount),
              let joined = String(data: data, encoding: .utf8),
              !joined.isEmpty
        else { return nil }
        return joined.split(separator: " ").map(String.init)
    }

    static func loadLegacyPassphrase() -> String? {
        guard let data = KeychainService.load(account: legacyPassphraseAccount),
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func clearLegacy() {
        _ = KeychainService.delete(account: legacyMnemonicAccount)
        _ = KeychainService.delete(account: legacyPassphraseAccount)
    }
}
