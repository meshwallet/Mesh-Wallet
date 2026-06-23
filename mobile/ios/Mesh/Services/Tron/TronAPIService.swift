import Foundation

enum TronAPIService {
    static func fetchAccountBalance(address: String) async -> TronAccountBalance {
        async let trxSignals = fetchTRXBalance(address: address)
        async let usdtBalance = fetchUSDTBalance(address: address)
        async let txCount = fetchTransactionCount(address: address)
        let (trx, _) = await trxSignals
        return TronAccountBalance(
            trxBalance: trx,
            usdtBalance: await usdtBalance ?? 0,
            transactionCount: await txCount
        )
    }

    /// Returns `nil` when TronGrid is unreachable or rate-limited (do not treat as zero balance).
    static func fetchUSDTBalance(address: String) async -> Double? {
        if let balance = await fetchUSDTBalanceFromTRC20Endpoint(address: address) {
            return balance
        }
        return await fetchUSDTBalanceFromAccountEndpoint(address: address)
    }

    /// `false` when the address has never received TRX (cannot receive TRC-20 yet).
    static func isAccountActivated(address: String) async -> Bool {
        let normalized = TronAddressCodec.normalizedBase58(address)
            ?? address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        if let viaV1 = await isAccountActivatedViaV1(normalized) {
            return viaV1
        }
        return await isAccountActivatedViaGetAccount(normalized)
    }

    /// TronGrid lists only on-chain accounts; empty `data` means the address was never funded.
    private static func isAccountActivatedViaV1(_ address: String) async -> Bool? {
        do {
            let data = try await TronAPIClient.get(path: "/v1/accounts/\(address)")
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["data"] as? [[String: Any]]
            else {
                return nil
            }
            guard let account = rows.first else {
                return false
            }
            return accountJSONIndicatesActivated(account)
        } catch {
            return nil
        }
    }

    private static func isAccountActivatedViaGetAccount(_ address: String) async -> Bool {
        do {
            let data = try await TronAPIClient.post(
                path: "/wallet/getaccount",
                jsonBody: ["address": address, "visible": true]
            )
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return accountJSONIndicatesActivated(json)
        } catch {
            return false
        }
    }

    private static func accountJSONIndicatesActivated(_ json: [String: Any]) -> Bool {
        if json.isEmpty {
            return false
        }
        if positiveInt64(json["create_time"]) != nil {
            return true
        }
        let balanceSun = int64Value(json["balance"]) ?? 0
        return balanceSun >= 1_000_000
    }

    private static func positiveInt64(_ value: Any?) -> Int64? {
        guard let parsed = int64Value(value), parsed > 0 else { return nil }
        return parsed
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let number as Int:
            return Int64(number)
        case let number as Int64:
            return number
        case let number as Double:
            return Int64(number)
        case let number as NSNumber:
            return number.int64Value
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Int64(trimmed)
        default:
            return nil
        }
    }

    static func fetchAccountResources(address: String) async throws -> TronAccountResources {
        let data = try await TronAPIClient.post(
            path: "/wallet/getaccountresource",
            jsonBody: ["address": address, "visible": true]
        )
        let decoded = try JSONDecoder().decode(TronAccountResourceResponse.self, from: data)
        let energy = (decoded.EnergyLimit ?? 0) - (decoded.EnergyUsed ?? 0)
        let freeNet = (decoded.freeNetLimit ?? 0) - (decoded.freeNetUsed ?? 0)
        let net = (decoded.NetLimit ?? 0) - (decoded.NetUsed ?? 0)
        let bandwidth = max(freeNet, net)
        let balance = await fetchTRXBalance(address: address).0
        return TronAccountResources(
            energyRemaining: Int64(max(energy, 0)),
            bandwidthRemaining: Int64(max(bandwidth, 0)),
            hasEnoughTRXForFees: balance >= 1.0 || energy > 0
        )
    }

    static func fetchUSDTTransactions(
        address: String,
        limit: Int = 20
    ) async throws -> [TronUSDTTransaction] {
        let query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "contract_address", value: TronConfiguration.usdtContractAddress),
            URLQueryItem(name: "only_confirmed", value: "true")
        ]
        let data = try await TronAPIClient.get(
            path: "/v1/accounts/\(address)/transactions/trc20",
            query: query
        )
        let decoded = try JSONDecoder().decode(TronTRC20HistoryResponse.self, from: data)
        return decoded.data.compactMap { item in
            mapHistoryItem(item, walletAddress: address)
        }
    }

    private static func fetchTRXBalance(address: String) async -> (Double, Int) {
        do {
            let data = try await TronAPIClient.post(
                path: "/wallet/getaccount",
                jsonBody: ["address": address, "visible": true]
            )
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (0, 0)
            }
            let raw = (json["balance"] as? Double) ?? Double(json["balance"] as? Int ?? 0)
            return (raw / 1_000_000.0, 0)
        } catch {
            return (0, 0)
        }
    }

    private static func fetchTransactionCount(address: String) async -> Int {
        do {
            let data = try await TronAPIClient.get(path: "/v1/accounts/\(address)")
            let decoded = try JSONDecoder().decode(TronGridAccountResponse.self, from: data)
            return decoded.data.first?.transactions ?? 0
        } catch {
            return 0
        }
    }

    /// Preferred: TronGrid TRC-20 balance endpoint (reliable for USDT).
    private static func fetchUSDTBalanceFromTRC20Endpoint(address: String) async -> Double? {
        do {
            let query = [
                URLQueryItem(name: "contract_address", value: TronConfiguration.usdtContractAddress),
                URLQueryItem(name: "limit", value: "1"),
            ]
            let data = try await TronAPIClient.get(
                path: "/v1/accounts/\(address)/trc20/balance",
                query: query
            )
            let decoded = try JSONDecoder().decode(TronTRC20BalanceResponse.self, from: data)
            for tokenMap in decoded.data {
                if let raw = tokenMap[TronConfiguration.usdtContractAddress] {
                    return parseUSDTBalanceString(raw)
                }
            }
            return 0
        } catch {
            return nil
        }
    }

    /// Fallback for older account payloads that embed `trc20` on `/v1/accounts/{address}`.
    private static func fetchUSDTBalanceFromAccountEndpoint(address: String) async -> Double? {
        do {
            let data = try await TronAPIClient.get(path: "/v1/accounts/\(address)")
            let decoded = try JSONDecoder().decode(TronGridAccountResponse.self, from: data)
            guard let trc20Tokens = decoded.data.first?.trc20 else { return 0 }

            for tokenMap in trc20Tokens {
                if let rawBalance = tokenMap[TronConfiguration.usdtContractAddress] {
                    return parseUSDTBalanceString(rawBalance)
                }
            }
            return 0
        } catch {
            return nil
        }
    }

    private static func parseUSDTBalanceString(_ raw: String) -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        if let units = UInt64(trimmed) {
            let decimal = TronAmountEncoder.smallestUnitsToUSDT(units)
            return (decimal as NSDecimalNumber).doubleValue
        }
        return Double(trimmed).map { $0 / pow(10, Double(TronConfiguration.tokenDecimals)) } ?? 0
    }

    private static func mapHistoryItem(
        _ item: TronTRC20HistoryItem,
        walletAddress: String
    ) -> TronUSDTTransaction? {
        guard let txID = item.transaction_id,
              let from = item.from,
              let to = item.to,
              let valueRaw = item.value,
              let timestampMs = item.block_timestamp
        else { return nil }

        let smallestUnits = UInt64(valueRaw) ?? UInt64(Double(valueRaw) ?? 0)
        let amount = TronAmountEncoder.smallestUnitsToUSDT(smallestUnits)
        // Classify relative to the address we queried — required for sends between own receive slots.
        let direction: TronTransactionDirection
        if TronAddressCodec.matches(from, walletAddress) {
            direction = .outgoing
        } else if TronAddressCodec.matches(to, walletAddress) {
            direction = .incoming
        } else {
            return nil
        }
        return TronUSDTTransaction(
            id: txID,
            txID: txID,
            fromAddress: from,
            toAddress: to,
            amount: amount,
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000),
            direction: direction
        )
    }

    private static func addressesMatch(_ lhs: String, _ rhs: String) -> Bool {
        TronAddressCodec.matches(lhs, rhs)
    }
}

private struct TronGridAccountResponse: Decodable {
    let data: [TronGridAccount]
}

private struct TronGridAccount: Decodable {
    let trc20: [[String: String]]?
    let transactions: Int?
}

private struct TronAccountResourceResponse: Decodable {
    let EnergyLimit: Int64?
    let EnergyUsed: Int64?
    let NetLimit: Int64?
    let NetUsed: Int64?
    let freeNetLimit: Int64?
    let freeNetUsed: Int64?
}

private struct TronTRC20BalanceResponse: Decodable {
    let data: [[String: String]]
}

private struct TronTRC20HistoryResponse: Decodable {
    let data: [TronTRC20HistoryItem]
}

private struct TronTRC20HistoryItem: Decodable {
    let transaction_id: String?
    let from: String?
    let to: String?
    let value: String?
    let block_timestamp: Int64?
}
