import Foundation

#if canImport(WalletCore)
/// Direct sends via `MeshSendRouter` — one tx splits USDT to recipient + treasury fee.
enum MeshSendRouterService {
    static var isConfigured: Bool {
        MeshSendFees.usesSendRouter
    }

    /// Signs, prepares network, and broadcasts a direct router send on-device.
    static func performOnDeviceDirectSend(
        spendSource: PrivacySpendSource,
        recipient: String,
        recipientAmount: Decimal,
        feeAmount: Decimal,
        statusUpdate: ((String) -> Void)? = nil
    ) async throws -> TronUSDTTransferResult {
        let signed = try await buildSignedDirectSend(
            spendSource: spendSource,
            recipient: recipient,
            recipientAmount: recipientAmount,
            feeAmount: feeAmount,
            statusUpdate: statusUpdate
        )
        statusUpdate?("Sending USDT…")
        let txID = try await TronTransactionService.broadcastSignedTransaction(
            rawJSON: signed.rawJSON
        )
        return TronUSDTTransferResult(txID: txID, rawJSON: signed.rawJSON)
    }

    /// Ensures USDT allowance for the router; signs and broadcasts approve when needed.
    static func ensureUSDTAllowance(
        ownerAddress: String,
        derivationPath: String,
        requiredTotal: UInt64,
        statusUpdate: ((String) -> Void)? = nil
    ) async throws {
        guard let router = MeshSendFees.sendRouterAddress else {
            throw TronAPIError.broadcastFailed("Send router is not configured.")
        }

        if try await currentAllowance(owner: ownerAddress, spender: router) >= requiredTotal {
            return
        }

        statusUpdate?("Authorizing USDT…")
        let signingKey = try MeshWalletCredentials.signingKey(derivationPath: derivationPath)

        let signed = try await TronSmartContractService.buildSignedApprove(
            signingKey: signingKey,
            fromAddress: ownerAddress,
            spender: router
        )
        _ = try await TronTransactionService.broadcastSignedTransaction(rawJSON: signed.rawJSON)
        try await waitForAllowance(
            owner: ownerAddress,
            spender: router,
            requiredTotal: requiredTotal
        )
    }

    /// Pre-signed txs for worker handoff — no on-device network prep or broadcast.
    struct HandoffSigningResult {
        let signedMainTxJSON: String?
        let signedMainTxSteps: [MeshQueuedSendStep]?
    }

    /// Signs router send (and optional USDT approve) locally; worker handles energy + broadcast.
    static func buildSignedDirectSendForHandoff(
        spendSource: PrivacySpendSource,
        recipient: String,
        recipientAmount: Decimal,
        feeAmount: Decimal,
        statusUpdate: ((String) -> Void)? = nil
    ) async throws -> HandoffSigningResult {
        guard let router = MeshSendFees.sendRouterAddress else {
            throw TronAPIError.broadcastFailed("Send router is not configured.")
        }

        let recipientUnits = try TronAmountEncoder.usdtToSmallestUnits(recipientAmount)
        let feeUnits = try TronAmountEncoder.usdtToSmallestUnits(feeAmount)
        let required = recipientUnits &+ feeUnits

        let signingKey = try MeshWalletCredentials.signingKey(
            derivationPath: spendSource.derivationPath
        )

        async let allowanceTask = currentAllowance(owner: spendSource.address, spender: router)
        async let blockTask = TronBlockService.fetchLatestBlock()
        let (allowance, chainBlock) = try await (allowanceTask, blockTask)

        var steps: [MeshQueuedSendStep] = []
        if allowance < required {
            statusUpdate?("Signing USDT authorization…")
            let signedApprove = try await TronSmartContractService.buildSignedApprove(
                signingKey: signingKey,
                fromAddress: spendSource.address,
                spender: router,
                chainBlock: chainBlock
            )
            steps.append(
                MeshQueuedSendStep(
                    fromAddress: spendSource.address,
                    toAddress: router,
                    amountUSDT: 0,
                    signedTxJSON: signedApprove.rawJSON,
                    highEnergy: false,
                    label: "router_approve"
                )
            )
        }

        statusUpdate?("Signing transfer…")
        let signedMain = try await TronSmartContractService.buildSignedSendWithFee(
            signingKey: signingKey,
            fromAddress: spendSource.address,
            routerAddress: router,
            recipient: recipient,
            recipientAmount: recipientAmount,
            feeAmount: feeAmount,
            chainBlock: chainBlock
        )

        if steps.isEmpty {
            return HandoffSigningResult(
                signedMainTxJSON: signedMain.rawJSON,
                signedMainTxSteps: nil
            )
        }

        steps.append(
            MeshQueuedSendStep(
                fromAddress: spendSource.address,
                toAddress: recipient,
                amountUSDT: NSDecimalNumber(decimal: recipientAmount).doubleValue,
                signedTxJSON: signedMain.rawJSON,
                highEnergy: true,
                label: "direct"
            )
        )
        return HandoffSigningResult(
            signedMainTxJSON: nil,
            signedMainTxSteps: steps
        )
    }

    static func buildSignedDirectSend(
        spendSource: PrivacySpendSource,
        recipient: String,
        recipientAmount: Decimal,
        feeAmount: Decimal,
        statusUpdate: ((String) -> Void)? = nil
    ) async throws -> TronUSDTTransferResult {
        guard let router = MeshSendFees.sendRouterAddress else {
            throw TronAPIError.broadcastFailed("Send router is not configured.")
        }

        let recipientUnits = try TronAmountEncoder.usdtToSmallestUnits(recipientAmount)
        let feeUnits = try TronAmountEncoder.usdtToSmallestUnits(feeAmount)
        let required = recipientUnits &+ feeUnits

        try await ensureUSDTAllowance(
            ownerAddress: spendSource.address,
            derivationPath: spendSource.derivationPath,
            requiredTotal: required,
            statusUpdate: statusUpdate
        )

        let signingKey = try MeshWalletCredentials.signingKey(
            derivationPath: spendSource.derivationPath
        )
        return try await TronSmartContractService.buildSignedSendWithFee(
            signingKey: signingKey,
            fromAddress: spendSource.address,
            routerAddress: router,
            recipient: recipient,
            recipientAmount: recipientAmount,
            feeAmount: feeAmount
        )
    }

    private static func currentAllowance(owner: String, spender: String) async throws -> UInt64 {
        if let cachedAllowance,
           cachedAllowanceOwner == owner,
           cachedAllowanceSpender == spender,
           let cachedAllowanceAt,
           Date().timeIntervalSince(cachedAllowanceAt) < allowanceCacheLifetime
        {
            return cachedAllowance
        }
        let value = try await TronSmartContractService.usdtAllowance(owner: owner, spender: spender)
        cachedAllowance = value
        cachedAllowanceOwner = owner
        cachedAllowanceSpender = spender
        cachedAllowanceAt = Date()
        return value
    }

    /// Warms allowance cache while the user reviews the send.
    static func prefetchAllowance(owner: String, router: String) {
        Task {
            _ = try? await currentAllowance(owner: owner, spender: router)
        }
    }

    private static var cachedAllowance: UInt64?
    private static var cachedAllowanceOwner: String?
    private static var cachedAllowanceSpender: String?
    private static var cachedAllowanceAt: Date?
    private static let allowanceCacheLifetime: TimeInterval = 30

    private static func waitForAllowance(
        owner: String,
        spender: String,
        requiredTotal: UInt64
    ) async throws {
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if try await currentAllowance(owner: owner, spender: spender) >= requiredTotal {
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw TronAPIError.broadcastFailed(
            "USDT authorization did not confirm in time. Try again."
        )
    }
}
#endif
