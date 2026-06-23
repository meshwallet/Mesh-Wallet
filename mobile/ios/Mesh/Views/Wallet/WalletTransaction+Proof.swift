import Foundation

extension WalletTransaction {
    var isProofEligible: Bool {
        switch transferStatus {
        case .confirmed, .processing:
            return true
        case .failed:
            return false
        }
    }

    var proofSubtitle: String {
        switch transferStatus {
        case .confirmed:
            return L10n.TransferProof.confirmedOnNetwork
        case .processing:
            return L10n.TransferProof.processingOnNetwork
        case .failed:
            return ""
        }
    }

    var proofHeadline: String {
        switch kind {
        case .sent:
            return L10n.TransferProof.transferSent
        case .received:
            return L10n.TransferProof.transferReceived
        }
    }

    var proofAmountText: String {
        "\(WalletAmountFormat.usdtDetail(abs(amountUSDT))) USDT"
    }

    var proofCleanHeadline: String {
        switch kind {
        case .sent:
            return L10n.TransferProof.amountSent(proofAmountText)
        case .received:
            return L10n.TransferProof.amountReceived(proofAmountText)
        }
    }

    var proofStatusText: String {
        switch transferStatus {
        case .confirmed:
            return L10n.TransferProof.confirmed
        case .processing:
            return L10n.Transaction.processing
        case .failed:
            return L10n.Send.failed
        }
    }

    var proofNetworkText: String {
        L10n.TransferProof.network
    }

    var proofCounterpartyTitle: String {
        kind == .sent ? L10n.TransferProof.to : L10n.TransferProof.from
    }

    var proofShortCounterparty: String {
        TronUSDTService.shortAddress(counterpartyAddress)
    }

    var proofShortTxID: String {
        guard !txID.isEmpty else { return "—" }
        return TronUSDTService.shortAddress(txID)
    }

    var proofBrandLine: String {
        kind == .sent ? L10n.TransferProof.sentWithMesh : L10n.TransferProof.receivedWithMesh
    }

    var proofShareText: String {
        [
            proofHeadline,
            "",
            proofAmountText,
            "",
            "\(L10n.TransferProof.status): \(proofStatusText)",
            "\(L10n.TransferProof.networkLabel): \(proofNetworkText)",
            "\(proofCounterpartyTitle): \(proofShortCounterparty)",
            "\(L10n.TransferProof.tx): \(proofShortTxID)",
            formattedDateTime,
            "",
            proofBrandLine,
            L10n.TransferProof.tagline,
        ].joined(separator: "\n")
    }
}
