import Foundation

#if canImport(WalletCore)
import WalletCore

/// ABI encoding for Mesh router / USDT calls (Ethereum-compatible).
enum MeshABIEncoder {
    static let approveSelector = Data(hex: "095ea7b3")!
    static let sendWithFeeSelector = Data(hex: "67156f76")!

  /// `parameter` field for Tron `triggersmartcontract` (no selector prefix).
    static func encodeSendWithFeeParameter(
        recipientBase58: String,
        recipientAmount: UInt64,
        feeAmount: UInt64
    ) throws -> String {
        guard let recipient = tronAddressWord(recipientBase58) else {
            throw TronAPIError.invalidAddress
        }
        var payload = Data()
        payload.append(recipient)
        payload.append(encodeUInt256Word(recipientAmount))
        payload.append(encodeUInt256Word(feeAmount))
        return payload.hexString
    }

    static func encodeApproveCallData(spenderBase58: String, amount: UInt64) throws -> Data {
        var data = approveSelector
        let parameter = try encodeApproveParameter(spenderBase58: spenderBase58, amount: amount)
        guard let bytes = Data(hex: parameter) else {
            throw TronAPIError.decodingFailed
        }
        data.append(bytes)
        return data
    }

    static func encodeSendWithFeeCallData(
        recipientBase58: String,
        recipientAmount: UInt64,
        feeAmount: UInt64
    ) throws -> Data {
        var data = sendWithFeeSelector
        let parameter = try encodeSendWithFeeParameter(
            recipientBase58: recipientBase58,
            recipientAmount: recipientAmount,
            feeAmount: feeAmount
        )
        guard let bytes = Data(hex: parameter) else {
            throw TronAPIError.decodingFailed
        }
        data.append(bytes)
        return data
    }

    static func encodeApproveParameter(spenderBase58: String, amount: UInt64) throws -> String {
        guard let spender = tronAddressWord(spenderBase58) else {
            throw TronAPIError.invalidAddress
        }
        var payload = Data()
        payload.append(spender)
        payload.append(encodeUInt256Word(amount))
        return payload.hexString
    }

    /// Parameters for `allowance(address,address)` (no selector).
    static func encodeAllowanceParameter(ownerBase58: String, spenderBase58: String) throws -> String {
        guard let owner = tronAddressWord(ownerBase58),
              let spender = tronAddressWord(spenderBase58)
        else {
            throw TronAPIError.invalidAddress
        }
        var payload = Data()
        payload.append(owner)
        payload.append(spender)
        return payload.hexString
    }

    private static func encodeUInt256Word(_ value: UInt64) -> Data {
        TronAmountEncoder.encodeUInt256(smallestUnits: value)
    }

    private static func tronAddressWord(_ address: String) -> Data? {
        TronAddressHex.addressWord(from: address)
    }
}

enum TronAddressHex {
    /// 32-byte ABI word for a Tron base58 or hex address.
    static func addressWord(from address: String) -> Data? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // WalletCore validates Tron via AnyAddress but `AnyAddress.data` is empty
        // (Tron CoinEntry does not implement addressToData). Decode base58 directly.
        if let payload = base58AddressPayload(from: trimmed),
           let word = word(fromAddressBytes: payload)
        {
            return word
        }

        if trimmed.lowercased().hasPrefix("41"), trimmed.count == 42,
           let raw = Data(hexString: trimmed),
           let word = word(fromAddressBytes: raw)
        {
            return word
        }

        if let parsed = AnyAddress(string: trimmed, coin: .tron),
           !parsed.data.isEmpty,
           let word = word(fromAddressBytes: parsed.data)
        {
            return word
        }

        return nil
    }

    private static func base58AddressPayload(from base58: String) -> Data? {
        guard AnyAddress(string: base58, coin: .tron) != nil else { return nil }

        if let decoded = Base58.decode(string: base58), decoded.count >= 21 {
            return Data(decoded.prefix(21))
        }
        if let raw = Base58.decodeNoCheck(string: base58), raw.count >= 21 {
            return Data(raw.prefix(21))
        }
        return nil
    }

    static func base58ToWordData(_ base58: String) -> Data? {
        addressWord(from: base58)
    }

    private static func word(fromAddressBytes raw: Data) -> Data? {
        let addressBytes: Data
        if raw.count == 21, raw.first == 0x41 {
            addressBytes = Data(raw.dropFirst())
        } else if raw.count == 20 {
            addressBytes = raw
        } else {
            return nil
        }
        guard addressBytes.count == 20 else { return nil }
        var word = Data(repeating: 0, count: 32)
        word.replaceSubrange(12..<32, with: addressBytes)
        return word
    }
}

private extension Data {
    init?(hex: String) {
        let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
#endif
