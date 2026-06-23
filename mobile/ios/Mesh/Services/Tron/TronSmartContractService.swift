import Foundation

#if canImport(WalletCore)
import WalletCore
import SwiftProtobuf

/// Builds and signs Tron smart-contract transactions via WalletCore + TronGrid read APIs.
enum TronSmartContractService {
    private static let routerFeeLimit: Int64 = 150_000_000
    private static let approveFeeLimit: Int64 = 80_000_000
    /// Max uint256 — one-time USDT approve for the Mesh router.
    private static let unlimitedAllowance: UInt64 = .max
    private static let expirationOffsetMs: Int64 = 3_600_000

    static func usdtAllowance(owner: String, spender: String) async throws -> UInt64 {
        let parameter = try MeshABIEncoder.encodeAllowanceParameter(
            ownerBase58: owner,
            spenderBase58: spender
        )
        let data = try await TronAPIClient.post(
            path: "/wallet/triggerconstantcontract",
            jsonBody: [
                "owner_address": owner,
                "contract_address": TronConfiguration.usdtContractAddress,
                "function_selector": "allowance(address,address)",
                "parameter": parameter,
                "visible": true,
            ]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["constant_result"] as? [String],
              let hex = results.first,
              let raw = Data(hexString: normalizeHex(hex)),
              raw.count >= 32
        else {
            return 0
        }
        let word = raw.suffix(32)
        return word.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    static func buildSignedApprove(
        signingKey: Data,
        fromAddress: String,
        spender: String,
        chainBlock: TronChainBlock? = nil
    ) async throws -> TronUSDTTransferResult {
        let callData = try MeshABIEncoder.encodeApproveCallData(
            spenderBase58: spender,
            amount: unlimitedAllowance
        )
        return try await signTriggerSmartContract(
            signingKey: signingKey,
            ownerAddress: fromAddress,
            contractAddress: TronConfiguration.usdtContractAddress,
            callData: callData,
            feeLimit: approveFeeLimit,
            chainBlock: chainBlock
        )
    }

    static func buildSignedSendWithFee(
        signingKey: Data,
        fromAddress: String,
        routerAddress: String,
        recipient: String,
        recipientAmount: Decimal,
        feeAmount: Decimal,
        chainBlock: TronChainBlock? = nil
    ) async throws -> TronUSDTTransferResult {
        let recipientUnits = try TronAmountEncoder.usdtToSmallestUnits(recipientAmount)
        let feeUnits = try TronAmountEncoder.usdtToSmallestUnits(feeAmount)
        let callData = try MeshABIEncoder.encodeSendWithFeeCallData(
            recipientBase58: recipient,
            recipientAmount: recipientUnits,
            feeAmount: feeUnits
        )
        return try await signTriggerSmartContract(
            signingKey: signingKey,
            ownerAddress: fromAddress,
            contractAddress: routerAddress,
            callData: callData,
            feeLimit: routerFeeLimit,
            chainBlock: chainBlock
        )
    }

    private static func signTriggerSmartContract(
        signingKey: Data,
        ownerAddress: String,
        contractAddress: String,
        callData: Data,
        feeLimit: Int64,
        chainBlock: TronChainBlock? = nil
    ) async throws -> TronUSDTTransferResult {
        guard AnyAddress(string: ownerAddress, coin: .tron) != nil,
              AnyAddress(string: contractAddress, coin: .tron) != nil
        else {
            throw TronAPIError.invalidAddress
        }

        let block: TronChainBlock
        if let chainBlock {
            block = chainBlock
        } else {
            block = try await TronBlockService.fetchLatestBlock()
        }
        let input = TronSigningInput.with {
            $0.privateKey = signingKey
            $0.transaction = TronTransaction.with {
                $0.timestamp = block.timestamp
                $0.expiration = block.timestamp + expirationOffsetMs
                $0.feeLimit = feeLimit
                $0.blockHeader = block.header
                $0.triggerSmartContract = TronTriggerSmartContract.with {
                    $0.ownerAddress = ownerAddress
                    $0.contractAddress = contractAddress
                    $0.callValue = 0
                    $0.data = callData
                }
            }
        }

        let output: TronSigningOutput = AnySigner.sign(input: input, coin: .tron)
        guard output.error == .ok, !output.json.isEmpty else {
            throw TronAPIError.broadcastFailed("Contract signing failed")
        }

        let broadcastBody = try jsonObject(from: output.json)
        let txID = (broadcastBody["txID"] as? String)
            ?? (broadcastBody["txid"] as? String)
            ?? ""
        return TronUSDTTransferResult(txID: txID, rawJSON: output.json)
    }

    private static func normalizeHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    private static func jsonObject(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw TronAPIError.decodingFailed
        }
        return object
    }
}
#endif
