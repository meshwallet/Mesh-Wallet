import Foundation

enum MeshPrivateKeyStore {
    private static func account(walletID: String) -> String {
        "mesh.tron.privatekey.\(walletID)"
    }

    static func saveHex(_ hex: String, walletID: String) {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let data = normalized.data(using: .utf8) else { return }
        guard KeychainService.save(data, account: account(walletID: walletID)) else {
            assertionFailure("Failed to save private key to Keychain")
            return
        }
    }

    static func loadHex(walletID: String) -> String? {
        guard let data = KeychainService.load(account: account(walletID: walletID)),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func clear(walletID: String) {
        _ = KeychainService.delete(account: account(walletID: walletID))
    }
}
