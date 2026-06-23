import Foundation

#if canImport(WalletCore)
import WalletCore

enum TronWalletError: LocalizedError, Equatable {
    case walletCreationFailed
    case invalidMnemonic
    case invalidPrivateKey
    case addressDerivationFailed

    var errorDescription: String? {
        switch self {
        case .walletCreationFailed:
            return "Could not generate a new wallet."
        case .invalidMnemonic:
            return "Invalid recovery phrase for this wallet."
        case .invalidPrivateKey:
            return "Invalid private key. Use 64 hex characters (32 bytes)."
        case .addressDerivationFailed:
            return "Could not derive Tron address from this key."
        }
    }
}

struct TronWalletSnapshot: Equatable {
    let address: String
    let derivationPath: String
}

enum TronWalletService {
    static func createWallet(passphrase: String = "") throws -> (mnemonic: [String], snapshot: TronWalletSnapshot) {
        guard let wallet = HDWallet(strength: 128, passphrase: passphrase) else {
            throw TronWalletError.walletCreationFailed
        }
        let words = wallet.mnemonic.split(separator: " ").map(String.init)
        guard let snapshot = snapshot(from: wallet) else {
            throw TronWalletError.addressDerivationFailed
        }
        return (words, snapshot)
    }

    static func importWallet(mnemonic: String, passphrase: String = "") throws -> TronWalletSnapshot {
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: passphrase) else {
            throw TronWalletError.invalidMnemonic
        }
        guard let snapshot = snapshot(from: wallet) else {
            throw TronWalletError.addressDerivationFailed
        }
        return snapshot
    }

    static func importWallet(words: [String], passphrase: String = "") throws -> TronWalletSnapshot {
        let mnemonic = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return try importWallet(mnemonic: mnemonic, passphrase: passphrase)
    }

    /// BIP-44 external receive path: `m/44'/195'/0'/0/{accountIndex}`.
    static func receiveDerivationPath(accountIndex: UInt32) -> String {
        "m/44'/195'/0'/0/\(accountIndex)"
    }

    /// One-time relay path (chain 1) — recipient only sees this address on-chain.
    static func relayDerivationPath(accountIndex: UInt32) -> String {
        "m/44'/195'/0'/1/\(accountIndex)"
    }

    static func deriveRelayAddress(
        accountIndex: UInt32,
        words: [String],
        passphrase: String = ""
    ) throws -> String {
        let mnemonic = normalizedMnemonic(words)
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: passphrase) else {
            throw TronWalletError.invalidMnemonic
        }
        let path = relayDerivationPath(accountIndex: accountIndex)
        let key = wallet.getKey(coin: .tron, derivationPath: path)
        return CoinType.tron.deriveAddress(privateKey: key)
    }

    static func deriveReceiveAddress(
        accountIndex: UInt32,
        words: [String],
        passphrase: String = ""
    ) throws -> String {
        let mnemonic = normalizedMnemonic(words)
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: passphrase) else {
            throw TronWalletError.invalidMnemonic
        }
        let path = receiveDerivationPath(accountIndex: accountIndex)
        let key = wallet.getKey(coin: .tron, derivationPath: path)
        return CoinType.tron.deriveAddress(privateKey: key)
    }

    static func importPrivateKey(hex: String) throws -> TronWalletSnapshot {
        let keyData = try privateKeyData(hex: hex)
        let address = try address(fromPrivateKey: keyData)
        return TronWalletSnapshot(address: address, derivationPath: "")
    }

    static func address(fromPrivateKey keyData: Data) throws -> String {
        guard let privateKey = PrivateKey(data: keyData) else {
            throw TronWalletError.invalidPrivateKey
        }
        let address = CoinType.tron.deriveAddress(privateKey: privateKey)
        guard !address.isEmpty, AnyAddress(string: address, coin: .tron) != nil else {
            throw TronWalletError.addressDerivationFailed
        }
        return address
    }

    static func privateKeyData(hex: String) throws -> Data {
        let normalized = try normalizePrivateKeyHex(hex)
        guard let privateKey = PrivateKey(data: normalized) else {
            throw TronWalletError.invalidPrivateKey
        }
        return privateKey.data
    }

    static func privateKeyData(
        mnemonic: String,
        passphrase: String = "",
        derivationPath: String = TronConfiguration.defaultDerivationPath
    ) throws -> Data {
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: passphrase) else {
            throw TronWalletError.invalidMnemonic
        }
        return wallet.getKey(coin: .tron, derivationPath: derivationPath).data
    }

    static func normalizePrivateKeyHex(_ input: String) throws -> Data {
        var hex = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        hex = hex.filter { !$0.isWhitespace }
        guard hex.count == 64 else {
            throw TronWalletError.invalidPrivateKey
        }
        guard let data = dataFromHex(hex) else {
            throw TronWalletError.invalidPrivateKey
        }
        return data
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard next <= hex.endIndex else { return nil }
            let byte = hex[index..<next]
            guard let value = UInt8(byte, radix: 16) else { return nil }
            data.append(value)
            index = next
        }
        return data
    }

    private static func normalizedMnemonic(_ words: [String]) -> String {
        words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func snapshot(from wallet: HDWallet) -> TronWalletSnapshot? {
        let address = wallet.getAddressForCoin(coin: .tron)
        guard !address.isEmpty else { return nil }
        return TronWalletSnapshot(
            address: address,
            derivationPath: TronConfiguration.defaultDerivationPath
        )
    }
}
#endif
