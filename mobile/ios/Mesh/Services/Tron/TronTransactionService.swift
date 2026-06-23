import Foundation

#if canImport(WalletCore)
import WalletCore
import SwiftProtobuf

enum TronTransactionService {
    static func sendUSDT(
        mnemonic: String,
        passphrase: String = "",
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        derivationPath: String = TronConfiguration.defaultDerivationPath,
        feeLimit: Int64 = TronConfiguration.defaultFeeLimit,
        skipNetworkPrepare: Bool = false
    ) async throws -> TronUSDTTransferResult {
        let privateKey = try TronWalletService.privateKeyData(
            mnemonic: mnemonic,
            passphrase: passphrase,
            derivationPath: derivationPath
        )
        return try await sendUSDT(
            signingKey: privateKey,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            feeLimit: feeLimit,
            skipNetworkPrepare: skipNetworkPrepare
        )
    }

    static func sendUSDT(
        signingKey: Data,
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        feeLimit: Int64 = TronConfiguration.defaultFeeLimit,
        skipNetworkPrepare: Bool = false
    ) async throws -> TronUSDTTransferResult {
        guard AnyAddress(string: toAddress, coin: .tron) != nil else {
            throw TronAPIError.invalidAddress
        }
        guard AnyAddress(string: fromAddress, coin: .tron) != nil else {
            throw TronAPIError.invalidAddress
        }

        if MeshNetworkSponsorship.isEnabled, !skipNetworkPrepare {
            try await MeshEnergyBrokerService.prepareSender(
                address: fromAddress,
                toAddress: toAddress,
                skipRecipientActivation: true
            )
        } else if !MeshNetworkSponsorship.isEnabled {
            guard await TronAPIService.isAccountActivated(address: fromAddress) else {
                throw TronAPIError.senderNotActivated(fromAddress)
            }
            let resources = try await TronAPIService.fetchAccountResources(address: fromAddress)
            guard resources.hasEnoughTRXForFees else {
                throw TronAPIError.insufficientTRXForFee
            }
        }

        let smallestUnits = try TronAmountEncoder.usdtToSmallestUnits(amount)
        let block = try await TronBlockService.fetchLatestBlock()
        let signed = try signUSDTTransaction(
            signingKey: signingKey,
            fromAddress: fromAddress,
            toAddress: toAddress,
            smallestUnits: smallestUnits,
            block: block,
            feeLimit: feeLimit,
            expirationOffsetMs: 3_600_000
        )

        let broadcastData = try await TronAPIClient.post(
            path: "/wallet/broadcasttransaction",
            jsonBody: signed.broadcastBody
        )
        let broadcast = try JSONDecoder().decode(TronBroadcastResponse.self, from: broadcastData)
        if broadcast.result == true, let txID = broadcast.txid, !txID.isEmpty {
            return TronUSDTTransferResult(txID: txID, rawJSON: signed.rawJSON)
        }
        if let recovered = await recoverBroadcastIfAlreadyOnChain(
            txID: signed.txID,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount
        ) {
            return recovered
        }
        let reason = broadcast.message ?? broadcast.code ?? "unknown"
        throw TronAPIError.broadcastFailed(reason)
    }

    private static func recoverBroadcastIfAlreadyOnChain(
        txID: String,
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        notBefore: Date = Date().addingTimeInterval(-120)
    ) async -> TronUSDTTransferResult? {
        guard await TronUSDTService.verifyOutgoingUSDTTransfer(
            txID: txID,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            notBefore: notBefore
        ) != nil else {
            return nil
        }
        return TronUSDTTransferResult(txID: txID, rawJSON: "")
    }

    /// Signs a USDT transfer without broadcasting (used for pre-signed Mesh fees).
    static func buildSignedUSDTTransaction(
        signingKey: Data,
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        feeLimit: Int64 = TronConfiguration.defaultFeeLimit,
        expirationOffsetMs: Int64 = TronConfiguration.presignedTransactionExpirationMs
    ) async throws -> TronUSDTTransferResult {
        guard AnyAddress(string: toAddress, coin: .tron) != nil else {
            throw TronAPIError.invalidAddress
        }
        guard AnyAddress(string: fromAddress, coin: .tron) != nil else {
            throw TronAPIError.invalidAddress
        }

        let smallestUnits = try TronAmountEncoder.usdtToSmallestUnits(amount)
        let block = try await TronBlockService.fetchLatestBlock()
        let signed = try signUSDTTransaction(
            signingKey: signingKey,
            fromAddress: fromAddress,
            toAddress: toAddress,
            smallestUnits: smallestUnits,
            block: block,
            feeLimit: feeLimit,
            expirationOffsetMs: expirationOffsetMs
        )
        return TronUSDTTransferResult(txID: signed.txID, rawJSON: signed.rawJSON)
    }

    /// Broadcast a previously signed transaction JSON (WalletCore / TronWeb format).
    static func broadcastSignedTransaction(rawJSON: String) async throws -> String {
        let broadcastBody = try jsonObject(from: rawJSON)
        let broadcastData = try await TronAPIClient.post(
            path: "/wallet/broadcasttransaction",
            jsonBody: broadcastBody
        )
        let broadcast = try JSONDecoder().decode(TronBroadcastResponse.self, from: broadcastData)
        guard broadcast.result == true, let txID = broadcast.txid, !txID.isEmpty else {
            let reason = broadcast.message ?? broadcast.code ?? "unknown"
            throw TronAPIError.broadcastFailed(reason)
        }
        return txID
    }

    private struct SignedUSDTTransaction {
        let txID: String
        let rawJSON: String
        let broadcastBody: [String: Any]
    }

    private static func signUSDTTransaction(
        signingKey: Data,
        fromAddress: String,
        toAddress: String,
        smallestUnits: UInt64,
        block: TronChainBlock,
        feeLimit: Int64,
        expirationOffsetMs: Int64
    ) throws -> SignedUSDTTransaction {
        let input = TronSigningInput.with {
            $0.transaction = TronTransaction.with {
                $0.timestamp = block.timestamp
                $0.expiration = block.timestamp + expirationOffsetMs
                $0.feeLimit = feeLimit
                $0.blockHeader = block.header
                $0.transferTrc20Contract = TronTransferTRC20Contract.with {
                    $0.ownerAddress = fromAddress
                    $0.contractAddress = TronConfiguration.usdtContractAddress
                    $0.toAddress = toAddress
                    $0.amount = TronAmountEncoder.encodeUInt256(smallestUnits: smallestUnits)
                }
            }
            $0.privateKey = signingKey
        }

        let output: TronSigningOutput = AnySigner.sign(input: input, coin: .tron)
        guard output.error == .ok, !output.json.isEmpty else {
            throw TronAPIError.broadcastFailed("Signing failed")
        }

        let broadcastBody = try jsonObject(from: output.json)
        let txID = (broadcastBody["txID"] as? String)
            ?? (broadcastBody["txid"] as? String)
            ?? ""

        return SignedUSDTTransaction(
            txID: txID,
            rawJSON: output.json,
            broadcastBody: broadcastBody
        )
    }

    /// Prepare Energy, wait until on-chain, then broadcast (private relay hops).
    static func sendUSDTWithSponsoredRetry(
        mnemonic: String,
        passphrase: String = "",
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        derivationPath: String,
        highEnergy: Bool = true,
        skipPrepare: Bool = false,
        maxAttempts: Int = 6
    ) async throws -> TronUSDTTransferResult {
        guard MeshNetworkSponsorship.isEnabled else {
            return try await sendUSDT(
                mnemonic: mnemonic,
                passphrase: passphrase,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amount,
                derivationPath: derivationPath
            )
        }

        let notBefore = Date().addingTimeInterval(-120)
        if let existing = await TronUSDTService.findRecentOutgoingUSDTTransfer(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            notBefore: notBefore
        ) {
            return TronUSDTTransferResult(txID: existing.txID, rawJSON: "")
        }

        if !skipPrepare {
            try await MeshEnergyBrokerService.prepareSender(
                address: fromAddress,
                toAddress: toAddress,
                highEnergy: highEnergy,
                skipRecipientActivation: true
            )
        }

        do {
            return try await sendUSDT(
                mnemonic: mnemonic,
                passphrase: passphrase,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amount,
                derivationPath: derivationPath,
                skipNetworkPrepare: true
            )
        } catch {
            if let existing = await TronUSDTService.findRecentOutgoingUSDTTransfer(
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amount,
                notBefore: notBefore
            ) {
                return TronUSDTTransferResult(txID: existing.txID, rawJSON: "")
            }
            throw error
        }
    }

    static func sendTRX(
        mnemonic: String,
        passphrase: String = "",
        fromAddress: String,
        toAddress: String,
        amountSun: Int64,
        derivationPath: String
    ) async throws -> TronUSDTTransferResult {
        guard amountSun > 0 else {
            throw TronAPIError.invalidAmount
        }
        guard AnyAddress(string: toAddress, coin: .tron) != nil,
              AnyAddress(string: fromAddress, coin: .tron) != nil
        else {
            throw TronAPIError.invalidAddress
        }

        let resources = try await TronAPIService.fetchAccountResources(address: fromAddress)
        guard resources.hasEnoughTRXForFees else {
            throw TronAPIError.insufficientTRXForFee
        }

        let block = try await TronBlockService.fetchLatestBlock()
        let privateKey = try TronWalletService.privateKeyData(
            mnemonic: mnemonic,
            passphrase: passphrase,
            derivationPath: derivationPath
        )

        let input = TronSigningInput.with {
            $0.transaction = TronTransaction.with {
                $0.timestamp = block.timestamp
                $0.expiration = block.timestamp + 3_600_000
                $0.blockHeader = block.header
                $0.transfer = TronTransferContract.with {
                    $0.ownerAddress = fromAddress
                    $0.toAddress = toAddress
                    $0.amount = amountSun
                }
            }
            $0.privateKey = privateKey
        }

        let output: TronSigningOutput = AnySigner.sign(input: input, coin: .tron)
        guard output.error == .ok, !output.json.isEmpty else {
            throw TronAPIError.broadcastFailed("Signing failed")
        }

        let broadcastData = try await TronAPIClient.post(
            path: "/wallet/broadcasttransaction",
            jsonBody: jsonObject(from: output.json)
        )
        let broadcast = try JSONDecoder().decode(TronBroadcastResponse.self, from: broadcastData)
        guard broadcast.result == true, let txID = broadcast.txid, !txID.isEmpty else {
            let reason = broadcast.message ?? broadcast.code ?? "unknown"
            throw TronAPIError.broadcastFailed(reason)
        }
        return TronUSDTTransferResult(txID: txID, rawJSON: output.json)
    }

    private static func jsonObject(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TronAPIError.decodingFailed
        }
        return object
    }
}

private struct TronBroadcastResponse: Decodable {
    let result: Bool?
    let txid: String?
    let code: String?
    let message: String?
}
#endif
