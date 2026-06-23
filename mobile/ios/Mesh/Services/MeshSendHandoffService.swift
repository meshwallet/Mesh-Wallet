import Foundation

/// Builds pre-signed direct sends for the worker queue.
enum MeshSendHandoffService {
    static func performHandoff(
        model: SendFlowViewModel,
        obligationID: String,
        directSpendSource: PrivacySpendSource? = nil,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws -> MeshSendHandoffResult {
        guard MeshNetworkSponsorship.isRelayConfigured else {
            throw TronAPIError.broadcastFailed(
                "Send service is temporarily unavailable. Please try again in a few minutes."
            )
        }

        guard SendAmountParser.parse(model.amountText) != nil else {
            throw TronAPIError.invalidAmount
        }

        let payout = model.recipientPayoutUSDT
        guard payout > 0 else {
            throw TronAPIError.invalidAmount
        }
        if MeshSendFees.showsFeeInUI,
           model.networkFeeUSDT > 0,
           model.enteredAmountUSDT <= model.networkFeeUSDT
        {
            throw TronAPIError.broadcastFailed(
                L10n.Error.amountBelowFee(model.networkFeeText)
            )
        }

        return try await performDirectHandoff(
            model: model,
            obligationID: obligationID,
            payout: payout,
            spendSource: directSpendSource,
            onProgress: onProgress
        )
    }

    private static func performDirectHandoff(
        model: SendFlowViewModel,
        obligationID: String,
        payout: Decimal,
        spendSource: PrivacySpendSource?,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws -> MeshSendHandoffResult {
        let recipient = model.recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        let source: PrivacySpendSource
        if let spendSource {
            source = spendSource
        } else {
            await onProgress("Preparing your transfer…")
            source = try await model.directSpendSourceForHandoff()
        }

        await onProgress("Signing transfer…")
        let highEnergy = await model.recipientNeedsHighEnergy(recipient: recipient)

        let signedMainJSON: String?
        let signedSteps: [MeshQueuedSendStep]?

        if MeshSendFees.usesSendRouter {
            let signing = try await MeshSendRouterService.buildSignedDirectSendForHandoff(
                spendSource: source,
                recipient: recipient,
                recipientAmount: payout,
                feeAmount: model.networkFeeUSDT,
                statusUpdate: { message in
                    Task { @MainActor in onProgress(message) }
                }
            )
            signedMainJSON = signing.signedMainTxJSON
            signedSteps = signing.signedMainTxSteps
        } else {
            let signingKey = try MeshWalletCredentials.signingKey(
                derivationPath: source.derivationPath
            )
            let signedMain = try await TronTransactionService.buildSignedUSDTTransaction(
                signingKey: signingKey,
                fromAddress: source.address,
                toAddress: recipient,
                amount: payout,
                expirationOffsetMs: TronConfiguration.handoffTransactionExpirationMs
            )
            signedMainJSON = signedMain.rawJSON
            signedSteps = nil
        }

        await onProgress("Sending to Mesh…")
        return MeshSendHandoffResult(
            obligationID: obligationID,
            userAddress: source.address,
            signedFeeTxJSON: nil,
            signedMainTxJSON: signedMainJSON,
            signedMainTxSteps: signedSteps,
            highEnergy: highEnergy,
            isPrivateSend: false,
            sendMode: "direct"
        )
    }
}
