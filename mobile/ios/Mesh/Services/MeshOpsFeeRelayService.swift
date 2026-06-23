import Foundation

/// Optional relay path: ops wallet pays USDT fee when the user wallet cannot broadcast fee tx.
enum MeshOpsFeeRelayService {
    struct PayFeeResponse: Decodable {
        let ok: Bool
        let message: String?
        let txID: String?
    }

    struct OpsStatusResponse: Decodable {
        let ok: Bool
        let usdt: Double?
    }

    /// True when ops has enough USDT to cover the fee (hidden fallback only).
    static func canPayFromOps(for fee: Decimal) async -> Bool {
        guard MeshNetworkSponsorship.isEnabled,
              let base = MeshNetworkSponsorship.relayBaseURL
        else { return false }

        guard let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/ops-status") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        if let secret = MeshNetworkSponsorship.relayAuthSecret {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await MeshHTTPClient.relayData(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(OpsStatusResponse.self, from: data),
              decoded.ok == true,
              let usdt = decoded.usdt
        else { return false }

        return Decimal(usdt) + Decimal(0.000001) >= fee
    }

    static func payNetworkFee(userAddress: String, fee: Decimal) async throws {
        guard MeshNetworkSponsorship.isEnabled else {
            throw TronAPIError.broadcastFailed("Send service is not enabled.")
        }
        guard let base = MeshNetworkSponsorship.relayBaseURL else {
            throw TronAPIError.broadcastFailed(
                "Send service is temporarily unavailable. Please try again in a few minutes."
            )
        }
        guard let treasury = MeshSendFees.treasuryAddress else {
            throw TronAPIError.broadcastFailed("Fee treasury is not configured.")
        }

        guard let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/pay-network-fee") else {
            throw TronAPIError.broadcastFailed("Send service URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "application/json")
        request.timeoutInterval = 120
        if let secret = MeshNetworkSponsorship.relayAuthSecret {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        let feeNumber = NSDecimalNumber(decimal: fee).doubleValue
        let body: [String: Any] = [
            "userAddress": userAddress,
            "feeUSDT": feeNumber,
            "treasury": treasury,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await MeshHTTPClient.relayData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TronAPIError.broadcastFailed("Network fee payment failed.")
        }

        let decoded = try? JSONDecoder().decode(PayFeeResponse.self, from: data)
        guard (200...299).contains(http.statusCode), decoded?.ok == true else {
            let detail = decoded?.message ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TronAPIError.broadcastFailed(detail)
        }
    }
}
