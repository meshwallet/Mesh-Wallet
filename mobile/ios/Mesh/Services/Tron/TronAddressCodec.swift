import Foundation

#if canImport(WalletCore)
import WalletCore

/// Normalizes Tron addresses (base58 / hex) for reliable comparison in history.
enum TronAddressCodec {
    static func normalizedBase58(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = AnyAddress(string: trimmed, coin: .tron) else {
            return trimmed
        }
        return parsed.description
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedBase58(lhs) ?? lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = normalizedBase58(rhs) ?? rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        return left == right
    }
}
#else
enum TronAddressCodec {
    static func normalizedBase58(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalizedBase58(lhs) == normalizedBase58(rhs)
    }
}
#endif
