import Foundation

/// Collects the fixed USDT send fee from the user's wallet to the Mesh treasury.
enum MeshFeeCollectionService {
    private static let maxAttempts = 3
    private static let feeReadyTimeoutSeconds = 45

    /// Signs a fee transfer (24h validity) for worker broadcast after the main send confirms.
    static func presignNetworkFee(
        fee: Decimal,
        spendSource: PrivacySpendSource
    ) async throws -> String {
        guard fee > 0, let treasury = MeshSendFees.treasuryAddress else {
            throw TronAPIError.broadcastFailed("Treasury not configured.")
        }

        let signingKey = try MeshWalletCredentials.signingKey(
            derivationPath: spendSource.derivationPath
        )
        let signed = try await TronTransactionService.buildSignedUSDTTransaction(
            signingKey: signingKey,
            fromAddress: spendSource.address,
            toAddress: treasury,
            amount: fee
        )
        return signed.rawJSON
    }

    /// Broadcast a pre-signed fee transaction (prepares Energy first).
    @discardableResult
    static func broadcastPresignedNetworkFee(
        rawJSON: String,
        spendSource: PrivacySpendSource
    ) async throws -> String {
        guard let treasury = MeshSendFees.treasuryAddress else {
            throw TronAPIError.broadcastFailed("Treasury not configured.")
        }

        if await MeshEnergyBrokerService.needsNetworkPrepare(
            address: spendSource.address,
            highEnergy: false
        ) {
            try await MeshEnergyBrokerService.prepareSender(
                address: spendSource.address,
                toAddress: treasury,
                highEnergy: false,
                skipRecipientActivation: true
            )
        }
        try await MeshEnergyBrokerService.requireSenderReady(
            address: spendSource.address,
            highEnergy: false,
            timeoutSeconds: feeReadyTimeoutSeconds
        )
        return try await TronTransactionService.broadcastSignedTransaction(rawJSON: rawJSON)
    }

    /// After private relay hops the funding wallet is often out of energy — ops USDT is faster.
    static func collectNetworkFeeViaOpsIfAvailable(
        userAddress: String,
        fee: Decimal
    ) async throws -> Bool {
        guard MeshNetworkSponsorship.isEnabled else { return false }

        do {
            try await MeshOpsFeeRelayService.payNetworkFee(userAddress: userAddress, fee: fee)
            return true
        } catch {
            return false
        }
    }

    static func collectNetworkFee(
        fee: Decimal,
        spendSource: PrivacySpendSource,
        preferOpsFallback: Bool = false
    ) async throws {
        guard fee > 0, let treasury = MeshSendFees.treasuryAddress else { return }

        if preferOpsFallback,
           try await collectNetworkFeeViaOpsIfAvailable(
               userAddress: spendSource.address,
               fee: fee
           )
        {
            return
        }

        let signingKey = try MeshWalletCredentials.signingKey(
            derivationPath: spendSource.derivationPath
        )

        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                if await MeshEnergyBrokerService.needsNetworkPrepare(
                    address: spendSource.address,
                    highEnergy: false
                ) {
                    try await MeshEnergyBrokerService.prepareSender(
                        address: spendSource.address,
                        toAddress: treasury,
                        highEnergy: false,
                        skipRecipientActivation: true
                    )
                }
                try await MeshEnergyBrokerService.requireSenderReady(
                    address: spendSource.address,
                    highEnergy: false,
                    timeoutSeconds: feeReadyTimeoutSeconds
                )
                _ = try await TronTransactionService.sendUSDT(
                    signingKey: signingKey,
                    fromAddress: spendSource.address,
                    toAddress: treasury,
                    amount: fee,
                    skipNetworkPrepare: true
                )
                return
            } catch {
                lastError = error
                if await tryOpsFeeFallback(
                    userAddress: spendSource.address,
                    fee: fee,
                    error: error,
                    allowOnEnergyErrors: true
                ) {
                    return
                }
                guard attempt < maxAttempts - 1,
                      MeshEnergyBrokerService.isEnergyRelatedError(error)
                else {
                    break
                }
                try await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }

        if try await collectNetworkFeeViaOpsIfAvailable(
            userAddress: spendSource.address,
            fee: fee
        ) {
            return
        }

        throw lastError ?? TronAPIError.broadcastFailed("Failed to collect send fee.")
    }

    private static func tryOpsFeeFallback(
        userAddress: String,
        fee: Decimal,
        error: Error,
        allowOnEnergyErrors: Bool = false
    ) async -> Bool {
        guard MeshNetworkSponsorship.isEnabled else { return false }

        let shouldFallback = isTransientNetworkError(error)
            || (allowOnEnergyErrors && MeshEnergyBrokerService.isEnergyRelatedError(error))
        guard shouldFallback else { return false }

        return (try? await collectNetworkFeeViaOpsIfAvailable(
            userAddress: userAddress,
            fee: fee
        )) == true
    }

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost,
                 .notConnectedToInternet,
                 .timedOut,
                 .cannotConnectToHost,
                 .dnsLookupFailed:
                return true
            default:
                break
            }
        }
        return error.localizedDescription.localizedCaseInsensitiveContains("connection was lost")
    }
}
