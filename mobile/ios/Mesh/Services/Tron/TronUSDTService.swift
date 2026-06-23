import Foundation

/// High-level USDT (TRC-20) operations for Mesh wallet.
enum TronUSDTService {
    static var isAPIConfigured: Bool {
        TronConfiguration.hasTronGridAPIKey
    }

    static func createWallet(passphrase: String = "") throws -> (mnemonic: [String], address: String) {
        #if canImport(WalletCore)
        let created = try TronWalletService.createWallet(passphrase: passphrase)
        return (created.mnemonic, created.snapshot.address)
        #else
        throw TronAPIError.decodingFailed
        #endif
    }

    static func importWallet(words: [String], passphrase: String = "") throws -> String {
        #if canImport(WalletCore)
        return try TronWalletService.importWallet(words: words, passphrase: passphrase).address
        #else
        throw TronAPIError.decodingFailed
        #endif
    }

    static func fetchBalance(address: String) async -> TronAccountBalance {
        await TronAPIService.fetchAccountBalance(address: address)
    }

    /// `nil` when TronGrid failed — not the same as a zero balance.
    static func fetchUSDTBalance(address: String) async -> Decimal? {
        guard let value = await TronAPIService.fetchUSDTBalance(address: address) else {
            return nil
        }
        return Decimal(value)
    }

    static func fetchResources(address: String) async throws -> TronAccountResources {
        try await TronAPIService.fetchAccountResources(address: address)
    }

    static func fetchTransactions(address: String, limit: Int = 20) async throws -> [TronUSDTTransaction] {
        let buffer = MeshSendFees.hasTreasury ? min(limit + 25, 200) : limit
        let raw = try await TronAPIService.fetchUSDTTransactions(address: address, limit: buffer)
        let hiddenRecipients = MeshPrivacyStore.privateSendRecipientMasks()
        return raw
            .filter { MeshSendFees.shouldShowInActivityHistory($0, hiddenPrivateRecipients: hiddenRecipients) }
            .prefix(limit)
            .map { $0 }
    }

    static func sendUSDT(
        to recipient: String,
        amount: Decimal,
        passphrase: String? = nil,
        spendSource: PrivacySpendSource? = nil,
        skipNetworkPrepare: Bool = false,
        chainGuardNotBefore: Date? = nil,
        statusUpdate: ((String) -> Void)? = nil
    ) async throws -> TronUSDTTransferResult {
        #if canImport(WalletCore)
        let resolved = try MeshWalletCredentials.resolve()

        let source: PrivacySpendSource
        if let spendSource {
            source = spendSource
        } else {
            source = PrivacySpendSource(
                address: resolved.address,
                derivationPath: resolved.derivationPath.isEmpty
                    ? TronWalletService.receiveDerivationPath(accountIndex: 0)
                    : resolved.derivationPath,
                accountIndex: 0,
                isPrivateSpend: false
            )
        }

        if source.derivationPath != resolved.derivationPath && resolved.importKind == .privateKey {
            throw TronAPIError.broadcastFailed("This wallet cannot sign from a derived address.")
        }

        let signingKey = try MeshWalletCredentials.signingKey(
            derivationPath: source.derivationPath
        )

        if MeshNetworkSponsorship.isEnabled || skipNetworkPrepare {
            return try await sendUSDTDirectBroadcast(
                signingKey: signingKey,
                fromAddress: source.address,
                toAddress: recipient,
                amount: amount,
                skipNetworkPrepare: skipNetworkPrepare,
                chainGuardNotBefore: chainGuardNotBefore,
                statusUpdate: statusUpdate
            )
        }

        return try await TronTransactionService.sendUSDT(
            signingKey: signingKey,
            fromAddress: source.address,
            toAddress: recipient,
            amount: amount,
            skipNetworkPrepare: skipNetworkPrepare
        )
        #else
        throw TronAPIError.decodingFailed
        #endif
    }

    /// Sign and broadcast — skips network prep when energy is already delegated.
    private static func sendUSDTDirectBroadcast(
        signingKey: Data,
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        skipNetworkPrepare: Bool = false,
        chainGuardNotBefore: Date? = nil,
        statusUpdate: ((String) -> Void)? = nil
    ) async throws -> TronUSDTTransferResult {
        let notBefore = chainGuardNotBefore ?? Date().addingTimeInterval(-120)
        let highEnergy = await recipientNeedsHighEnergy(toAddress: toAddress)

        if MeshNetworkSponsorship.isEnabled, !skipNetworkPrepare {
            let alreadyReady = !(await MeshEnergyBrokerService.needsNetworkPrepare(
                address: fromAddress,
                highEnergy: highEnergy
            ))
            if !alreadyReady {
                try await MeshEnergyBrokerService.ensureSenderReadyForBroadcast(
                    address: fromAddress,
                    toAddress: toAddress,
                    highEnergy: highEnergy,
                    timeoutSeconds: 30,
                    statusUpdate: networkPrepStatusHandler(for: statusUpdate)
                )
            }
        }

        statusUpdate?("Sending USDT…")
        do {
            return try await TronTransactionService.sendUSDT(
                signingKey: signingKey,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amount,
                skipNetworkPrepare: true
            )
        } catch {
            if MeshNetworkSponsorship.isEnabled, TronAPIError.isEnergyOrBandwidthIssue(error) {
                try await MeshEnergyBrokerService.ensureSenderReadyForBroadcast(
                    address: fromAddress,
                    toAddress: toAddress,
                    highEnergy: highEnergy,
                    timeoutSeconds: 45,
                    statusUpdate: networkPrepStatusHandler(for: statusUpdate)
                )
                statusUpdate?("Sending USDT…")
                do {
                    return try await TronTransactionService.sendUSDT(
                        signingKey: signingKey,
                        fromAddress: fromAddress,
                        toAddress: toAddress,
                        amount: amount,
                        skipNetworkPrepare: true
                    )
                } catch {
                    if let existing = await findRecentOutgoingUSDTTransfer(
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

            if let existing = await findRecentOutgoingUSDTTransfer(
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

    private static func recipientNeedsHighEnergy(toAddress: String) async -> Bool {
        guard MeshNetworkSponsorship.isEnabled else { return false }
        guard let balance = await fetchUSDTBalance(address: toAddress) else {
            return false
        }
        return balance <= 0
    }

    static func persistWallet(words: [String], passphrase: String = "") {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return }
        MeshMnemonicStore.saveWords(words, walletID: walletID)
        if !passphrase.isEmpty {
            MeshMnemonicStore.savePassphrase(passphrase, walletID: walletID)
        }
    }

    static func currentAddress() throws -> String {
        #if canImport(WalletCore)
        if let cached = WalletSession.cachedAddress(), !cached.isEmpty {
            return cached
        }
        return try MeshWalletCredentials.resolve().address
        #else
        throw TronAPIError.decodingFailed
        #endif
    }

    /// Tron transaction IDs are 64-character hex strings (not obligation UUIDs).
    static func isPlausibleTronTransactionID(_ txID: String) -> Bool {
        let hex = txID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hex.count == 64 else { return false }
        return hex.allSatisfy(\.isHexDigit)
    }

    /// Returns a recent outbound USDT transfer matching this send (used to avoid duplicate broadcasts).
    static func findRecentOutgoingUSDTTransfer(
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        notBefore: Date
    ) async -> TronUSDTTransaction? {
        await verifyOutgoingUSDTTransfer(
            txID: "",
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            notBefore: notBefore
        )
    }

    /// Confirms an outbound USDT transfer exists on-chain for this send.
    static func verifyOutgoingUSDTTransfer(
        txID: String,
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        notBefore: Date
    ) async -> TronUSDTTransaction? {
        let tolerance = Decimal(string: "0.000001") ?? 0
        let recipient = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let spendFrom = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let earliest = notBefore.addingTimeInterval(-5)

        func matches(_ tx: TronUSDTTransaction) -> Bool {
            guard tx.direction == .outgoing else { return false }
            guard TronAddressCodec.matches(tx.toAddress, recipient) else { return false }
            if !spendFrom.isEmpty, !TronAddressCodec.matches(tx.fromAddress, spendFrom) {
                return false
            }
            let delta = tx.amount - amount
            guard delta >= -tolerance, delta <= tolerance else { return false }
            return tx.timestamp >= earliest
        }

        var addressesToScan: [String] = []
        if !spendFrom.isEmpty {
            addressesToScan.append(spendFrom)
        }
        if MeshWalletCredentials.supportsHDWalletFeatures(),
           let credentials = try? MeshWalletCredentials.resolve(),
           let words = credentials.mnemonic
        {
            for index in MeshPrivacyStore.monitoredReceiveIndices(walletID: credentials.walletID) {
                if let derived = try? TronWalletService.deriveReceiveAddress(
                    accountIndex: index,
                    words: words,
                    passphrase: credentials.passphrase
                ), !addressesToScan.contains(where: { TronAddressCodec.matches($0, derived) }) {
                    addressesToScan.append(derived)
                }
            }
        } else if spendFrom.isEmpty, let main = try? currentAddress() {
            addressesToScan.append(main)
        }

        let trimmedTxID = txID.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPlausibleTronTransactionID(trimmedTxID) {
            func matchesKnownTxID(_ tx: TronUSDTTransaction) -> Bool {
                guard tx.txID == trimmedTxID, tx.direction == .outgoing else { return false }
                guard TronAddressCodec.matches(tx.toAddress, recipient) else { return false }
                let delta = tx.amount - amount
                guard delta >= -tolerance, delta <= tolerance else { return false }
                return tx.timestamp >= earliest
            }

            for address in addressesToScan {
                guard let history = try? await fetchTransactions(address: address, limit: 80) else {
                    continue
                }
                if let hit = history.first(where: matchesKnownTxID) {
                    return hit
                }
            }
        }

        for address in addressesToScan {
            guard let history = try? await fetchTransactions(address: address, limit: 80) else {
                continue
            }
            if let hit = history.first(where: matches) {
                return hit
            }
        }
        return nil
    }

    private static func networkPrepStatusHandler(
        for statusUpdate: ((String) -> Void)?
    ) -> ((MeshEnergyBrokerService.NetworkPrepStatus) -> Void)? {
        guard let statusUpdate else { return nil }
        return { phase in
            statusUpdate(networkPrepStatusMessage(phase))
        }
    }

    private static func networkPrepStatusMessage(
        _ phase: MeshEnergyBrokerService.NetworkPrepStatus
    ) -> String {
        switch phase {
        case .preparing:
            return "Preparing network…"
        case .requestingEnergy:
            return "Requesting network energy…"
        case .waitingEnergy:
            return "Waiting for network energy…"
        case .waitingResources:
            return "Waiting for network resources…"
        case .preparingBandwidth:
            return "Preparing network bandwidth…"
        case .waitingBandwidth:
            return "Waiting for network bandwidth…"
        case .retrying:
            return "Mesh is retrying network preparation…"
        }
    }
}
