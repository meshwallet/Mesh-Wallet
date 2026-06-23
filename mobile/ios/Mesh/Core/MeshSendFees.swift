import Foundation

/// Fixed send fees shown to the user (USDT). Mesh subsidizes on-chain TRX/Energy via worker / ops wallet.
enum MeshSendFees {
    /// Direct send when private mode is off.
    static let directSend: Decimal = 2
    /// Private send (1 intermediate wallet).
    static let standardPrivate: Decimal = 10

    /// UI-only fees for now — no on-chain collection.
    static let chargesOnChainFee = false

    /// Treasury/router fee collection and backend delinquent tracking.
    static var enforcesOnChainSendFees: Bool {
        chargesOnChainFee && hasTreasury
    }

    /// Always show $2 / $10 in send UI (review, send type picker, ticker).
    static let showsFeeInUI = true

    /// Fee shown in UI and used for balance validation when `chargesOnChainFee` is true.
    static func networkFee(isPrivateSend: Bool, mode: MeshPrivateSendMode) -> Decimal {
        if isPrivateSend {
            return standardPrivate
        }
        return directSend
    }

    /// Whether we collect the fee on-chain for this send mode.
    static func collectsSendFee(isPrivateSend: Bool) -> Bool {
        guard chargesOnChainFee, hasTreasury else { return false }
        if isPrivateSend { return true }
        return usesSendRouter
    }

    /// Relay `register-send-fee` payload — 0 when fees are UI-only.
    static func workerRegistrationFee(isPrivateSend: Bool, mode: MeshPrivateSendMode) -> Decimal {
        guard chargesOnChainFee else { return 0 }
        if isPrivateSend {
            return standardPrivate
        }
        return directSend
    }

    static var treasuryAddress: String? {
        let plist = Bundle.main.object(forInfoDictionaryKey: "MESH_FEE_TREASURY_ADDRESS") as? String
        let trimmed = plist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, TronUSDTService.isValidTronAddress(trimmed) { return trimmed }
        return nil
    }

    static var hasTreasury: Bool { treasuryAddress != nil }

    static var sendRouterAddress: String? {
        let plist = Bundle.main.object(forInfoDictionaryKey: "MESH_SEND_ROUTER_ADDRESS") as? String
        let trimmed = plist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, TronUSDTService.isValidTronAddress(trimmed) { return trimmed }
        return nil
    }

    /// Direct sends use router + treasury for a single USDT split transaction.
    static var usesSendRouter: Bool {
        chargesOnChainFee && hasTreasury && sendRouterAddress != nil
    }

    static var directFeeBundledInMainTx: Bool {
        usesSendRouter
    }

    static func registersFeeWithWorkerBeforeSend(isPrivateSend: Bool) -> Bool {
        guard collectsSendFee(isPrivateSend: isPrivateSend) else { return false }
        if isPrivateSend { return true }
        return !directFeeBundledInMainTx
    }

    static func initialNetworkFeeCollected(isPrivateSend: Bool) -> Bool {
        guard chargesOnChainFee else { return true }
        if isPrivateSend {
            return !collectsSendFee(isPrivateSend: true)
        }
        if directFeeBundledInMainTx {
            return false
        }
        return !collectsSendFee(isPrivateSend: false)
    }

    static func formattedFee(_ fee: Decimal) -> String {
        TronUSDTService.formatUSDTAmount(fee, includeSymbol: true)
    }

    static func shouldShowInActivityHistory(
        _ transaction: TronUSDTTransaction,
        hiddenPrivateRecipients: Set<String> = []
    ) -> Bool {
        if !isPlausibleHistoryAmount(transaction.amount) {
            return false
        }

        if transaction.direction == .outgoing {
            if let router = sendRouterAddress,
               tronAddressesMatch(transaction.toAddress, router)
            {
                return false
            }
            if let treasury = treasuryAddress,
               tronAddressesMatch(transaction.toAddress, treasury)
            {
                return false
            }
            if hiddenPrivateRecipients.contains(where: { tronAddressesMatch($0, transaction.toAddress) }) {
                return false
            }
        }

        return true
    }

    static func isPlausibleHistoryAmount(_ amount: Decimal) -> Bool {
        amount > 0 && amount < 1_000_000_000
    }

    private static func tronAddressesMatch(_ a: String, _ b: String) -> Bool {
        TronAddressCodec.matches(a, b)
    }
}
