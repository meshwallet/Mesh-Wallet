import Foundation

enum TronConfiguration {
    static let networkName = "Tron Mainnet"
    static let coinSymbol = "TRX"
    static let tokenSymbol = "USDT"
    static let tokenDecimals = 6
    static let defaultFeeLimit: Int64 = 30_000_000
    /// Pre-signed fee txs remain valid for worker broadcast (Tron max ~24h).
    static let presignedTransactionExpirationMs: Int64 = 86_400_000

    /// Worker handoff: sign → activate → broadcast must finish within this window.
    static let handoffTransactionExpirationMs: Int64 = 10 * 60 * 1_000

    /// TRX sent to a fresh relay address so it can pay the final USDT transfer fee.
    static let relayTRXTopUpSun: Int64 = 5_000_000

    /// Minimum TRX on the funding wallet for a single relay hop.
    static let relayFundingMinTRXPerHop: Double = 10

    static func relayFundingMinTRX(hopCount: Int) -> Double {
        Double(max(hopCount, 1)) * relayFundingMinTRXPerHop + 5
    }

    /// TRC-20 USDT on Tron mainnet.
    static let usdtContractAddress = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

    static let defaultDerivationPath = "m/44'/195'/0'/0/0"
    static let tronGridBaseURL = "https://api.trongrid.io"

    static let keychainMnemonicAccount = "mesh.tron.mnemonic"
    static let keychainPassphraseAccount = "mesh.tron.passphrase"

    /// All TronGrid keys (pool). Prefer `TRONGRID_API_KEYS` array in Info.plist.
    static var trongridAPIKeys: [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        func append(_ raw: String?) {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return }
            seen.insert(trimmed)
            ordered.append(trimmed)
        }

        if let plistKeys = Bundle.main.object(forInfoDictionaryKey: "TRONGRID_API_KEYS") as? [String] {
            for key in plistKeys { append(key) }
        }

        if let envList = ProcessInfo.processInfo.environment["TRONGRID_API_KEYS"]?
            .split(separator: ",")
        {
            for part in envList { append(String(part)) }
        }

        append(Bundle.main.object(forInfoDictionaryKey: "TRONGRID_API_KEY") as? String)
        append(ProcessInfo.processInfo.environment["TRONGRID_API_KEY"])
        append(UserDefaults.standard.string(forKey: "TRONGRID_API_KEY"))

        return ordered
    }

    /// Primary key — first entry in the pool (legacy call sites).
    static var trongridAPIKey: String? {
        trongridAPIKeys.first
    }

    static var hasTronGridAPIKey: Bool {
        !trongridAPIKeys.isEmpty
    }
}
