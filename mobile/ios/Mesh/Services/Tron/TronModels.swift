import Foundation

struct TronAccountBalance: Equatable {
    let trxBalance: Double
    let usdtBalance: Double
    let transactionCount: Int
}

struct TronAccountResources: Equatable {
    let energyRemaining: Int64
    let bandwidthRemaining: Int64
    let hasEnoughTRXForFees: Bool
}

struct TronUSDTTransferResult: Equatable {
    let txID: String
    let rawJSON: String
}

struct TronUSDTTransaction: Identifiable, Equatable {
    let id: String
    let txID: String
    let fromAddress: String
    let toAddress: String
    let amount: Decimal
    let timestamp: Date
    let direction: TronTransactionDirection
}

enum TronTransactionDirection: String, Equatable {
    case incoming
    case outgoing
}

enum TronAPIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpStatus(Int, String)
    case rateLimited
    case decodingFailed
    case broadcastFailed(String)
    case insufficientTRXForFee
    case invalidAmount
    case invalidAddress
    case recipientNotActivated(String)
    case senderNotActivated(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "TronGrid API keys are not configured. Add TRONGRID_API_KEYS to Info.plist (free at trongrid.io)."
        case .invalidURL:
            return "Invalid Tron API URL."
        case .httpStatus(let code, let body):
            return "Tron API HTTP \(code): \(body)"
        case .rateLimited:
            return "Tron network is busy. Please try again in a moment."
        case .decodingFailed:
            return "Failed to decode Tron API response."
        case .broadcastFailed(let reason):
            let presented = Self.presentableBroadcastReason(reason)
            if let friendly = Self.friendlyBroadcastMessage(presented) {
                return friendly
            }
            return presented
        case .recipientNotActivated:
            return "This recipient address cannot receive USDT yet. Please try again later."
        case .senderNotActivated:
            return "Your wallet is not ready to send yet. Please try again later."
        case .insufficientTRXForFee:
            return "Unable to complete this transfer. Please try again later."
        case .invalidAmount:
            return "Invalid USDT amount."
        case .invalidAddress:
            return "Invalid Tron address."
        }
    }

    static func presentableBroadcastReason(_ raw: String) -> String {
        let decoded = decodeTronHexMessage(raw) ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = decoded.lowercased()

        if lower.contains("not enough usdt") {
            return decoded
        }
        if lower.contains("429")
            || lower.contains("rate limit")
            || lower.contains("too many requests")
            || lower.contains("too many subrequests")
        {
            return SendErrorPresenter.rateLimitUserMessage
        }
        if lower.contains("bandwidth") {
            return "Network bandwidth was not ready yet. Wait a moment and try again."
        }
        if lower.contains("out_of_energy")
            || lower.contains("out of energy")
            || lower.contains("account resource insufficient")
            || lower.contains("resource insufficient")
            || (lower.contains("energy") && lower.contains("not ready"))
        {
            return "Network energy was not ready yet. Wait a moment and try again."
        }
        if lower.contains("did not activate in time")
            || (lower.contains("activate") && lower.contains("in time"))
        {
            return "This address is still activating on Tron. Wait about a minute and try again."
        }
        if lower.contains("account") && (lower.contains("not exist") || lower.contains("does not exist")) {
            return "This address is not activated on Tron yet. Wait about a minute and try again."
        }
        if lower.contains("tronnrg") && lower.contains("verify") {
            return "Network provider is busy. Please try again in a minute."
        }
        if lower.contains("could not verify usdt balance") {
            return decoded
        }
        if decoded.isEmpty || lower == "unknown" {
            return "Transfer was rejected by the network. Please try again."
        }
        return decoded
    }

    private static func decodeTronHexMessage(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexCandidate = trimmed
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? trimmed
        guard hexCandidate.count >= 4, hexCandidate.count % 2 == 0,
              hexCandidate.allSatisfy(\.isHexDigit)
        else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(hexCandidate.count / 2)
        var index = hexCandidate.startIndex
        while index < hexCandidate.endIndex {
            let next = hexCandidate.index(index, offsetBy: 2)
            guard let byte = UInt8(hexCandidate[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        guard let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        let clean = text.trimmingCharacters(in: .controlCharacters)
        return clean.isEmpty ? nil : clean
    }

    private static func friendlyBroadcastMessage(_ reason: String) -> String? {
        let lower = reason.lowercased()
        if lower.contains("ops wallet needs more trx") {
            return "Mesh ops wallet needs more TRX to sponsor this send. \(reason)"
        }
        if lower.contains("ops wallet needs usdt float") {
            return "Mesh ops wallet needs more USDT. \(reason)"
        }
        if lower.contains("relay not configured") {
            return "Mesh send relay is not configured on the server."
        }
        return nil
    }

    static func isEnergyOrBandwidthIssue(_ error: Error) -> Bool {
        let text: String
        if let tron = error as? TronAPIError, case .broadcastFailed(let reason) = tron {
            text = reason.lowercased()
        } else {
            text = error.localizedDescription.lowercased()
        }
        return text.contains("energy")
            || text.contains("bandwidth")
            || text.contains("resource insufficient")
            || text.contains("account resource")
    }
}
