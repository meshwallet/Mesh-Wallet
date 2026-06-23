import Foundation

struct WalletTransaction: Identifiable {
    enum Kind {
        case sent
        case received
    }

    enum TransferStatus: Equatable {
        case processing
        case confirmed
        case failed(String)

        var title: String {
            switch self {
            case .processing: return L10n.Transaction.processing
            case .confirmed: return L10n.Transaction.sent
            case .failed: return L10n.Send.failed
            }
        }

        var detailSubtitle: String {
            switch self {
            case .processing:
                return "Transfer is processing in the background. Status will update automatically."
            case .confirmed:
                return "Transfer was broadcast to the Tron network."
            case .failed(let message):
                return TronAPIError.presentableBroadcastReason(message)
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let amountUSDT: Decimal
    let dayLabel: String
    let txID: String
    let fromAddress: String
    let toAddress: String
    let timestamp: Date
    var transferStatus: TransferStatus

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        title: String,
        subtitle: String,
        amountUSDT: Decimal,
        dayLabel: String,
        txID: String = UUID().uuidString,
        fromAddress: String = "",
        toAddress: String = "",
        timestamp: Date = Date(),
        transferStatus: TransferStatus = .confirmed
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.amountUSDT = amountUSDT
        self.dayLabel = dayLabel
        self.txID = txID
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.timestamp = timestamp
        self.transferStatus = transferStatus
    }

    init(tron: TronUSDTTransaction) {
        let txKind: Kind = tron.direction == .incoming ? .received : .sent
        id = tron.txID
        kind = txKind
        title = txKind == .sent ? L10n.Transaction.sent : L10n.Transaction.received
        subtitle = Self.subtitle(for: tron)
        amountUSDT = tron.amount
        dayLabel = Self.dayLabel(for: tron.timestamp)
        txID = tron.txID
        fromAddress = tron.fromAddress
        toAddress = tron.toAddress
        timestamp = tron.timestamp
        transferStatus = .confirmed
    }

    var isProcessing: Bool {
        if case .processing = transferStatus { return true }
        return false
    }

    var listTitle: String {
        switch transferStatus {
        case .processing:
            return kind == .sent ? "Sending" : "Receiving"
        case .failed:
            return kind == .sent ? "Send failed" : title
        case .confirmed:
            return title
        }
    }

    var listSubtitle: String {
        switch transferStatus {
        case .failed(let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(activityLine) · \(transferStatus.title)" : detail
        case .processing:
            return "\(activityLine) · \(transferStatus.title)"
        case .confirmed:
            return activityLine
        }
    }

    var failureDetailText: String? {
        guard case .failed(let message) = transferStatus else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TronAPIError.presentableBroadcastReason(trimmed)
    }

    var displayTxID: String {
        guard !txID.isEmpty else { return "—" }
        return txID
    }

    /// List / home preview — always shows cents (e.g. 58.00).
    var amountText: String {
        signedAmount(prefix: kind == .received ? "+" : "-", value: WalletAmountFormat.usdtList(abs(amountUSDT)))
    }

    /// Detail screen — up to 6 decimals, trailing zeros trimmed (e.g. 58.125).
    var amountDetailText: String {
        signedAmount(prefix: kind == .received ? "+" : "-", value: WalletAmountFormat.usdtDetail(abs(amountUSDT)))
    }

    private func signedAmount(prefix: String, value: String) -> String {
        "\(prefix)\(value) USDT"
    }

    var isIncoming: Bool { kind == .received }

    /// Re-label sent/received for the focused receive account (self-transfers between HD slots).
    func oriented(forAccount account: String) -> WalletTransaction? {
        let focused = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !focused.isEmpty else { return nil }

        let fromHere = TronAddressCodec.matches(fromAddress, focused)
        let toHere = TronAddressCodec.matches(toAddress, focused)
        guard fromHere || toHere else { return nil }

        let orientedKind: Kind = toHere && !fromHere ? .received : .sent
        guard orientedKind != kind
            || (orientedKind == .sent && title != L10n.Transaction.sent)
            || (orientedKind == .received && title != L10n.Transaction.received)
        else { return self }

        let counterparty = orientedKind == .sent ? toAddress : fromAddress
        let short = TronUSDTService.shortAddress(counterparty)
        let orientedSubtitle = orientedKind == .sent ? short : "from \(short)"
        let orientedTitle = orientedKind == .sent ? L10n.Transaction.sent : L10n.Transaction.received

        return WalletTransaction(
            id: id,
            kind: orientedKind,
            title: orientedTitle,
            subtitle: orientedSubtitle,
            amountUSDT: amountUSDT,
            dayLabel: dayLabel,
            txID: txID,
            fromAddress: fromAddress,
            toAddress: toAddress,
            timestamp: timestamp,
            transferStatus: transferStatus
        )
    }

    var counterpartyAddress: String {
        kind == .sent ? toAddress : fromAddress
    }

    /// Single-line subtitle for activity list (counterparty).
    var activityLine: String {
        let short = TronUSDTService.shortAddress(counterpartyAddress)
        return kind == .sent ? "To \(short)" : "From \(short)"
    }

    var formattedDateTime: String {
        MeshAppDateFormat.mediumDateTime(timestamp)
    }

    /// Time only — trailing column on home / activity rows.
    var listRowTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: timestamp)
    }

    var tronscanURL: URL? {
        URL(string: "https://tronscan.org/#/transaction/\(txID)")
    }

    private static func subtitle(for tron: TronUSDTTransaction) -> String {
        switch tron.direction {
        case .outgoing:
            return TronUSDTService.shortAddress(tron.toAddress)
        case .incoming:
            return "from \(TronUSDTService.shortAddress(tron.fromAddress))"
        }
    }

    /// Section header in activity list — day + month; year when not the current calendar year.
    static func activitySectionDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L10n.Wallet.today }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let includesYear = calendar.component(.year, from: date)
            != calendar.component(.year, from: Date())
        formatter.setLocalizedDateFormatFromTemplate(includesYear ? "dMMMMyyyy" : "dMMMM")
        return titleStyleDate(formatter.string(from: date))
    }

    private static func titleStyleDate(_ raw: String) -> String {
        raw
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func dayLabel(for date: Date) -> String {
        activitySectionDateLabel(for: date)
    }
}

extension Array where Element == WalletTransaction {
    func groupedByDayLabel() -> [(day: String, items: [WalletTransaction])] {
        var order: [String] = []
        var buckets: [String: [WalletTransaction]] = [:]
        for tx in self {
            if buckets[tx.dayLabel] == nil {
                order.append(tx.dayLabel)
                buckets[tx.dayLabel] = []
            }
            buckets[tx.dayLabel, default: []].append(tx)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

enum WalletAmountFormat {
    /// History rows: 2 decimal places.
    static func usdtList(_ amount: Decimal) -> String {
        format(amount, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    /// Detail: full TRC-20 precision (6 decimals max), at least 2 fractional digits.
    static func usdtDetail(_ amount: Decimal) -> String {
        let raw = format(amount, minimumFractionDigits: 2, maximumFractionDigits: 6)
        return trimTrailingFractionZeros(raw, minimumPlaces: 2)
    }

    static func usdt(_ amount: Decimal) -> String {
        usdtList(amount)
    }

    private static func format(
        _ amount: Decimal,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0.00"
    }

    private static func trimTrailingFractionZeros(_ value: String, minimumPlaces: Int) -> String {
        guard let dot = value.firstIndex(of: ".") else { return value }
        let whole = value[..<dot]
        var fraction = String(value[value.index(after: dot)...])
        while fraction.count > minimumPlaces, fraction.last == "0" {
            fraction.removeLast()
        }
        return "\(whole).\(fraction)"
    }
}
