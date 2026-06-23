import Foundation

/// High-level wallet lifecycle: generate, restore, persist (Tron + BIP-39).
enum MeshWalletService {
    struct CreationResult: Equatable {
        let words: [String]
        let address: String
    }

    enum ActivationError: LocalizedError {
        case invalidPhrase(ValidatResult)
        case invalidPrivateKey
        case duplicateWalletName
        case walletCoreUnavailable
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .invalidPhrase(let result):
                switch result {
                case .valid:
                    return "Invalid recovery phrase."
                case .invalidWordCount(_, let actual):
                    return "Expected 12, 15, 18, 21, or 24 words. Current: \(actual)."
                case .invalidWord(let position, _):
                    return "Word \(position) is not in the BIP-39 word list."
                case .invalidChecksum:
                    return "Invalid checksum. Verify order and spelling."
                }
            case .invalidPrivateKey:
                return "Invalid private key. Use 64 hex characters (32 bytes)."
            case .duplicateWalletName:
                return L10n.Error.walletNameTaken
            case .walletCoreUnavailable:
                return "Wallet engine is not available in this build."
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    /// Generates a new 12-word Tron wallet locally (not persisted until `activateWallet`).
    static func generateWallet() throws -> CreationResult {
        #if canImport(WalletCore)
        let created = try TronUSDTService.createWallet()
        let words = normalizeWords(created.mnemonic)
        return CreationResult(words: words, address: created.address)
        #else
        throw ActivationError.walletCoreUnavailable
        #endif
    }

    /// Validates phrase, derives Tron address, saves to Keychain. Does not mark onboarding complete.
    static func importWallet(words: [String]) throws -> String {
        #if canImport(WalletCore)
        let normalized = normalizeWords(words)
        let validation = Valida.validateMnemonic(words: normalized)
        guard validation == .valid else {
            throw ActivationError.invalidPhrase(validation)
        }
        return try TronUSDTService.importWallet(words: normalized)
        #else
        throw ActivationError.walletCoreUnavailable
        #endif
    }

    /// Validates a Tron private key and returns the derived address (not persisted).
    static func importPrivateKey(_ rawKey: String) throws -> String {
        #if canImport(WalletCore)
        do {
            return try TronWalletService.importPrivateKey(hex: rawKey).address
        } catch let error as TronWalletError {
            if case .invalidPrivateKey = error {
                throw ActivationError.invalidPrivateKey
            }
            throw ActivationError.underlying(error)
        } catch {
            throw ActivationError.underlying(error)
        }
        #else
        throw ActivationError.walletCoreUnavailable
        #endif
    }

    /// Persists mnemonic and caches address after user confirms backup or restore.
    @discardableResult
    static func activateWallet(words: [String], name: String? = nil) throws -> String {
        #if canImport(WalletCore)
        try validateCustomWalletName(name)
        let normalized = normalizeWords(words)
        let address = try importWallet(words: normalized)
        let walletID = WalletSession.registerWallet(words: normalized, address: address, name: name)
        guard MeshMnemonicStore.loadWords(walletID: walletID) != nil else {
            throw ActivationError.underlying(
                NSError(domain: "MeshWallet", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to save wallet to secure storage."
                ])
            )
        }
        return address
        #else
        throw ActivationError.walletCoreUnavailable
        #endif
    }

    /// Persists a raw Tron private key in Keychain (no recovery phrase).
    @discardableResult
    static func activateWallet(privateKeyHex: String, expectedAddress: String, name: String? = nil) throws -> String {
        #if canImport(WalletCore)
        try validateCustomWalletName(name)
        let normalizedHex: String
        do {
            let keyData = try TronWalletService.normalizePrivateKeyHex(privateKeyHex)
            normalizedHex = keyData.map { String(format: "%02x", $0) }.joined()
        } catch {
            throw ActivationError.invalidPrivateKey
        }

        let address = try importPrivateKey(normalizedHex)
        guard address == expectedAddress.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ActivationError.underlying(
                NSError(domain: "MeshWallet", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Derived address does not match."
                ])
            )
        }

        let walletID = MeshWalletRegistry.registerPrivateKeyWallet(
            privateKeyHex: normalizedHex,
            address: address,
            name: name
        )
        guard MeshPrivateKeyStore.loadHex(walletID: walletID) != nil else {
            throw ActivationError.underlying(
                NSError(domain: "MeshWallet", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to save wallet to secure storage."
                ])
            )
        }
        if let wallet = MeshWalletRegistry.wallet(id: walletID) {
            UserDefaults.standard.set(wallet.address, forKey: "mesh.wallet.address")
        }
        return address
        #else
        throw ActivationError.walletCoreUnavailable
        #endif
    }

    static func normalizePrivateKeyInput(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace }
            .lowercased()
    }

    static func isValidPrivateKeyFormat(_ input: String) -> Bool {
        let hex = normalizePrivateKeyInput(input)
        guard hex.count == 64 else { return false }
        return hex.allSatisfy(\.isHexDigit)
    }

    static func normalizeWords(_ words: [String]) -> [String] {
        words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func normalizePhrase(_ phrase: String) -> [String] {
        normalizeWords(
            phrase
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
        )
    }

    /// Clipboard paste for restore — caps at 24 BIP-39 words so the editor stays responsive.
    static func sanitizedPhrasePaste(_ raw: String) -> String {
        let capped = String(raw.prefix(8_000))
        return normalizePhrase(capped).prefix(24).joined(separator: " ")
    }

    private static func validateCustomWalletName(_ name: String?) throws {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        if MeshWalletRegistry.isWalletNameTaken(trimmed) {
            throw ActivationError.duplicateWalletName
        }
    }
}
