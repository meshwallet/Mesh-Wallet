import Foundation

#if canImport(WalletCore)
import WalletCore

enum MeshWalletCredentials {
    struct Resolved: Equatable {
        let walletID: String
        let address: String
        let importKind: WalletImportKind
        let privateKey: Data
        let mnemonic: [String]?
        let passphrase: String
        let derivationPath: String
    }

    static func resolve(walletID: String? = MeshWalletRegistry.activeWalletID) throws -> Resolved {
        guard let walletID = walletID ?? MeshWalletRegistry.activeWalletID,
              let wallet = MeshWalletRegistry.wallet(id: walletID)
        else {
            throw TronAPIError.broadcastFailed("Wallet is not initialized")
        }

        switch wallet.importKind {
        case .mnemonic:
            guard let words = MeshMnemonicStore.loadWords(walletID: walletID),
                  Valida.allowedMnemonicWordCounts.contains(words.count)
            else {
                throw TronAPIError.broadcastFailed("Wallet is not initialized")
            }
            let passphrase = MeshMnemonicStore.loadPassphrase(walletID: walletID) ?? ""
            let path = TronConfiguration.defaultDerivationPath
            let mnemonic = words.joined(separator: " ")
            let snapshot = try TronWalletService.importWallet(words: words, passphrase: passphrase)
            guard snapshot.address == wallet.address else {
                throw TronAPIError.broadcastFailed("Wallet address mismatch.")
            }
            let privateKey = try TronWalletService.privateKeyData(
                mnemonic: mnemonic,
                passphrase: passphrase,
                derivationPath: path
            )
            return Resolved(
                walletID: walletID,
                address: wallet.address,
                importKind: .mnemonic,
                privateKey: privateKey,
                mnemonic: words,
                passphrase: passphrase,
                derivationPath: path
            )

        case .privateKey:
            guard let hex = MeshPrivateKeyStore.loadHex(walletID: walletID) else {
                throw TronAPIError.broadcastFailed("Wallet is not initialized")
            }
            let privateKey = try TronWalletService.privateKeyData(hex: hex)
            let derived = try TronWalletService.address(fromPrivateKey: privateKey)
            guard derived == wallet.address else {
                throw TronAPIError.broadcastFailed("Wallet address mismatch.")
            }
            return Resolved(
                walletID: walletID,
                address: wallet.address,
                importKind: .privateKey,
                privateKey: privateKey,
                mnemonic: nil,
                passphrase: "",
                derivationPath: ""
            )
        }
    }

    static func supportsHDWalletFeatures(walletID: String? = MeshWalletRegistry.activeWalletID) -> Bool {
        guard let walletID = walletID ?? MeshWalletRegistry.activeWalletID,
              let wallet = MeshWalletRegistry.wallet(id: walletID)
        else { return false }
        return wallet.importKind == .mnemonic
    }

    static func signingKey(
        walletID: String? = MeshWalletRegistry.activeWalletID,
        derivationPath: String? = nil
    ) throws -> Data {
        let resolved = try resolve(walletID: walletID)
        guard let path = derivationPath, !path.isEmpty, path != resolved.derivationPath else {
            return resolved.privateKey
        }
        guard let words = resolved.mnemonic else {
            throw TronAPIError.broadcastFailed("This wallet cannot sign from a derived address.")
        }
        return try TronWalletService.privateKeyData(
            mnemonic: words.joined(separator: " "),
            passphrase: resolved.passphrase,
            derivationPath: path
        )
    }
}
#endif
