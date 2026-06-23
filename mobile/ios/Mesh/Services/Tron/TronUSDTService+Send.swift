import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

extension TronUSDTService {
    static func isValidTronAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        #if canImport(WalletCore)
        return AnyAddress(string: trimmed, coin: .tron) != nil
        #else
        return trimmed.hasPrefix("T") && trimmed.count == 34
        #endif
    }

    static func formatUSDTAmount(_ amount: Decimal, includeSymbol: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = ","
        let value = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0,00"
        return includeSymbol ? "\(value) USDT" : value
    }

    static func shortAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return trimmed }
        let start = trimmed.prefix(6)
        let end = trimmed.suffix(4)
        return "\(start)…\(end)"
    }
}

enum SendAmountParser {
    /// Keeps digits and at most one decimal separator (max 2 fractional digits).
    static func sanitizeInput(_ text: String) -> String {
        var result = ""
        var hasSeparator = false
        var fractionDigits = 0

        for character in text {
            if character.isNumber {
                if hasSeparator {
                    guard fractionDigits < 2 else { continue }
                    fractionDigits += 1
                }
                result.append(character)
            } else if character == "." || character == "," {
                guard !hasSeparator else { continue }
                hasSeparator = true
                result.append(character)
            }
        }

        return result
    }

    static func parse(_ text: String) -> Decimal? {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        normalized = normalized
            .replacingOccurrences(of: "USDT", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")

        if normalized.contains(",") && normalized.contains(".") {
            if let lastComma = normalized.lastIndex(of: ","),
               let lastDot = normalized.lastIndex(of: ".") {
                if lastComma > lastDot {
                    normalized = normalized.replacingOccurrences(of: ".", with: "")
                    normalized = normalized.replacingOccurrences(of: ",", with: ".")
                } else {
                    normalized = normalized.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if normalized.contains(",") {
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        }

        guard let decimal = Decimal(string: normalized), decimal > 0 else { return nil }
        return decimal
    }
}
