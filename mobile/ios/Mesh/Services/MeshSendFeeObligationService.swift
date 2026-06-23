import Foundation

/// Backend tracking for send fees: register on send start, poll delinquent status, clear after user pays.
enum MeshSendFeeObligationService {
    struct FeeStatusResponse: Decodable {
        let ok: Bool
        let delinquent: Bool?
        let feeUSDT: Double?
        let obligationId: String?
        let mainTxID: String?
        let message: String?
    }

    struct RegisterResponse: Decodable {
        let ok: Bool
        let id: String?
        let queued: Bool?
        let message: String?
        let mainTxID: String?
        let status: String?
    }

    struct SendStatusResponse: Decodable {
        let ok: Bool
        let id: String?
        let status: String?
        let mainTxID: String?
        let feeTxID: String?
        let lastError: String?
        let lastStepLabel: String?
        let lastStepTxID: String?
        let currentStepIndex: Int?
        let totalSteps: Int?
        let networkStartedAtMs: Double?
        let updatedAtMs: Double?
        let queueAttempts: Int?
        let hasSignedMain: Bool?
        let isPrivateSend: Bool?
        let message: String?
    }

    private static func relayURL(path: String) -> URL? {
        guard let base = MeshNetworkSponsorship.relayBaseURL else { return nil }
        let trimmed = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmed)\(path)")
    }

    private static func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let secret = MeshNetworkSponsorship.relayAuthSecret {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func registerSendFee(
        id: String,
        userAddress: String,
        recipientAddress: String,
        amountUSDT: Decimal,
        feeUSDT: Decimal,
        startedAt: Date,
        signedFeeTxJSON: String? = nil,
        isPrivateSend: Bool = false,
        sendMode: String = "legacy"
    ) async {
        _ = try? await registerQueuedSend(
            handoff: MeshSendHandoffResult(
                obligationID: id,
                userAddress: userAddress,
                signedFeeTxJSON: signedFeeTxJSON,
                signedMainTxJSON: nil,
                signedMainTxSteps: nil,
                highEnergy: false,
                isPrivateSend: isPrivateSend,
                sendMode: sendMode
            ),
            userAddress: userAddress,
            recipientAddress: recipientAddress,
            amountUSDT: amountUSDT,
            feeUSDT: feeUSDT,
            startedAt: startedAt
        ).queued
    }

    struct SettleSendFeeResponse: Decodable {
        let ok: Bool
        let settled: Bool?
        let feeTxID: String?
        let feeCollectedVia: String?
        let message: String?
    }

    /// After on-device private send: attach main tx + funding address and collect fee on worker.
    @discardableResult
    static func settleSendFee(
        obligationId: String,
        mainTxID: String,
        fundingAddress: String
    ) async -> Bool {
        guard MeshNetworkSponsorship.isRelayConfigured,
              let url = relayURL(path: "/v1/settle-send-fee")
        else { return false }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "id": obligationId,
            "mainTxID": mainTxID,
            "fundingAddress": fundingAddress,
        ])

        guard let (data, response) = try? await MeshHTTPClient.relayData(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SettleSendFeeResponse.self, from: data),
              decoded.ok == true
        else { return false }

        return decoded.settled == true && !(decoded.feeTxID?.isEmpty ?? true)
    }

    /// Direct worker-queued send: collect fee on worker (presigned or ops), not on device.
    @discardableResult
    static func settleQueuedSendFee(obligationId: String) async -> Bool {
        guard MeshNetworkSponsorship.isRelayConfigured,
              let url = relayURL(path: "/v1/settle-queued-send-fee")
        else { return false }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "id": obligationId,
        ])

        guard let (data, response) = try? await MeshHTTPClient.relayData(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SettleSendFeeResponse.self, from: data),
              decoded.ok == true
        else { return false }

        return decoded.settled == true && !(decoded.feeTxID?.isEmpty ?? true)
    }

    struct RegisterSendResult {
        let queued: Bool
        let mainTxID: String?
        let status: String?
    }

    @discardableResult
    static func registerQueuedSend(
        handoff: MeshSendHandoffResult,
        userAddress: String,
        recipientAddress: String,
        amountUSDT: Decimal,
        feeUSDT: Decimal,
        startedAt: Date
    ) async throws -> RegisterSendResult {
        guard MeshNetworkSponsorship.isRelayConfigured,
              let url = relayURL(path: "/v1/register-send-fee")
        else {
            throw TronAPIError.broadcastFailed(
                "Send service is temporarily unavailable. Please try again in a few minutes."
            )
        }

        guard feeUSDT >= 0 else {
            throw TronAPIError.broadcastFailed(
                "Send service requires a valid feeUSDT for registration."
            )
        }
        if feeUSDT <= 0, !MeshSendFees.chargesOnChainFee {
            // UI-only fee — worker accepts zero with userFeeWaived.
        } else if feeUSDT <= 0 {
            throw TronAPIError.broadcastFailed(
                "Send service requires a positive feeUSDT for registration."
            )
        }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = handoff.isPrivateSend ? 120 : 60

        let body = registerBody(
            handoff: handoff,
            userAddress: userAddress,
            recipientAddress: recipientAddress,
            amountUSDT: amountUSDT,
            feeUSDT: feeUSDT,
            startedAt: startedAt
        )
        let payload = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = payload

        let (data, response) = try await relayDataWithRateLimitRetry(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode
        guard let httpStatus, (200...299).contains(httpStatus) else {
            let detail = SendErrorPresenter.relayFailureMessage(
                data: data,
                httpStatus: httpStatus
            )
            throw TronAPIError.broadcastFailed(detail)
        }

        let decoded = try JSONDecoder().decode(RegisterResponse.self, from: data)
        guard decoded.ok else {
            throw TronAPIError.broadcastFailed(decoded.message ?? "Send registration failed")
        }
        return RegisterSendResult(
            queued: decoded.queued == true,
            mainTxID: decoded.mainTxID,
            status: decoded.status
        )
    }

    static func encodeHandoffResumeJSON(
        handoff: MeshSendHandoffResult,
        userAddress: String,
        recipientAddress: String,
        amountUSDT: Decimal,
        feeUSDT: Decimal,
        startedAt: Date
    ) -> String? {
        let body = registerBody(
            handoff: handoff,
            userAddress: userAddress,
            recipientAddress: recipientAddress,
            amountUSDT: amountUSDT,
            feeUSDT: feeUSDT,
            startedAt: startedAt
        )
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func registerBody(
        handoff: MeshSendHandoffResult,
        userAddress: String,
        recipientAddress: String,
        amountUSDT: Decimal,
        feeUSDT: Decimal,
        startedAt: Date
    ) -> [String: Any] {
        var body: [String: Any] = [
            "id": handoff.obligationID,
            "userAddress": userAddress,
            "recipientAddress": recipientAddress,
            "amountUSDT": NSDecimalNumber(decimal: amountUSDT).doubleValue,
            "feeUSDT": NSDecimalNumber(decimal: feeUSDT).doubleValue,
            "startedAtMs": Int(startedAt.timeIntervalSince1970 * 1000),
            "highEnergy": handoff.highEnergy,
            "isPrivateSend": handoff.isPrivateSend,
            "sendMode": handoff.sendMode,
        ]

        if let signedFeeTxJSON = handoff.signedFeeTxJSON, !signedFeeTxJSON.isEmpty {
            body["signedFeeTxJSON"] = signedFeeTxJSON
        }
        if let signedMainTxJSON = handoff.signedMainTxJSON, !signedMainTxJSON.isEmpty {
            body["signedMainTxJSON"] = signedMainTxJSON
        }
        if let steps = handoff.signedMainTxSteps, !steps.isEmpty {
            body["signedMainTxSteps"] = steps.map { step in
                [
                    "fromAddress": step.fromAddress,
                    "toAddress": step.toAddress,
                    "amountUSDT": step.amountUSDT,
                    "signedTxJSON": step.signedTxJSON,
                    "highEnergy": step.highEnergy,
                    "label": step.label,
                ] as [String: Any]
            }
        }
        if !MeshSendFees.collectsSendFee(isPrivateSend: handoff.isPrivateSend) {
            body["userFeeWaived"] = true
        }
        return body
    }

    static func fetchFeeStatus(userAddress: String) async -> FeeStatusResponse? {
        guard MeshNetworkSponsorship.isRelayConfigured,
              var components = URLComponents(
                url: relayURL(path: "/v1/wallet-fee-status") ?? URL(fileURLWithPath: "/"),
                resolvingAgainstBaseURL: false
              )
        else { return nil }

        components.queryItems = [URLQueryItem(name: "address", value: userAddress)]
        guard let url = components.url else { return nil }

        let request = authorizedRequest(url: url, method: "GET")
        guard let (data, response) = try? await MeshHTTPClient.relayData(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(FeeStatusResponse.self, from: data),
              decoded.ok
        else { return nil }

        return decoded
    }

    static func fetchSendStatus(obligationId: String) async -> SendStatusResponse? {
        guard MeshNetworkSponsorship.isRelayConfigured,
              var components = URLComponents(
                url: relayURL(path: "/v1/send-status") ?? URL(fileURLWithPath: "/"),
                resolvingAgainstBaseURL: false
              )
        else { return nil }

        components.queryItems = [URLQueryItem(name: "id", value: obligationId)]
        guard let url = components.url else { return nil }

        let request = authorizedRequest(url: url, method: "GET")
        guard let (data, response) = try? await MeshHTTPClient.relayData(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SendStatusResponse.self, from: data),
              decoded.ok
        else { return nil }

        return decoded
    }

    /// Blocks until Mesh worker has actually started network work (safe to close the app).
    static func waitForWorkerNetworkStart(
        obligationId: String,
        timeout: TimeInterval = 90,
        requireNetworkStarted: Bool = true,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws {
        guard requireNetworkStarted else {
            await nudgeWorkerContinue(obligationId: obligationId)
            await onProgress("Mesh accepted your send — finishing on network…")
            return
        }
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(timeout)
        var lastNudgeAt = Date.distantPast

        await nudgeWorkerContinue(obligationId: obligationId)

        while Date() < deadline {
            try Task.checkCancellation()

            guard let status = await fetchSendStatus(obligationId: obligationId) else {
                await onProgress("Connecting to Mesh…")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }

            if status.hasSignedMain == false {
                throw TronAPIError.broadcastFailed(
                    "Mesh did not receive your signed transfer. Please try again."
                )
            }

            if let txID = status.mainTxID, !txID.isEmpty {
                await onProgress("Transfer submitted on network.")
                return
            }

            if workerNetworkHasStarted(status) {
                await onProgress(workerProgressMessage(from: status, started: true))
                return
            }

            switch status.status {
            case "send_confirmed_fee_pending", "settled":
                await onProgress(workerProgressMessage(from: status, started: true))
                return
            case "failed":
                let detail = status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let lower = detail.lowercased()
                if status.isPrivateSend == true, !isPermanentWorkerError(lower) {
                    await onProgress(retryWaitProgressMessage(lower))
                    await nudgeWorkerIfStale(obligationId: obligationId, lastNudgeAt: &lastNudgeAt)
                    break
                }
                if isRetryableWorkerWaitError(lower),
                   Date().timeIntervalSince(startedAt) < timeout - 15
                {
                    await onProgress(retryWaitProgressMessage(lower))
                    await nudgeWorkerIfStale(obligationId: obligationId, lastNudgeAt: &lastNudgeAt)
                    break
                }
                throw TronAPIError.broadcastFailed(
                    detail.isEmpty
                        ? "Send failed on Mesh network."
                        : detail
                )
            case "queued":
                if status.isPrivateSend == true {
                    let step = status.currentStepIndex ?? 0
                    if step > 0 || !(status.lastStepTxID?.isEmpty ?? true) {
                        await onProgress(workerProgressMessage(from: status, started: true))
                        return
                    }
                    if let err = status.lastError?.lowercased(), isRetryableWorkerWaitError(err) {
                        await onProgress(retryWaitProgressMessage(err))
                        await nudgeWorkerIfStale(obligationId: obligationId, lastNudgeAt: &lastNudgeAt)
                    } else if status.networkStartedAtMs != nil {
                        await onProgress("Mesh is preparing your private route on network…")
                    } else {
                        await onProgress("Preparing private route — step 1…")
                    }
                } else {
                    await onProgress("Mesh accepted — starting on network…")
                }
            case "processing_queue":
                await onProgress(workerProgressMessage(from: status, started: true))
                return
            case "pending":
                throw TronAPIError.broadcastFailed(
                    "Mesh did not queue this send. Please try again."
                )
            default:
                await onProgress("Confirming with Mesh…")
            }

            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        throw TronAPIError.broadcastFailed(
            "Mesh did not start your send in time. Keep the app open and try again."
        )
    }

    private static func isRetryableWorkerWaitError(_ lower: String) -> Bool {
        if lower.isEmpty { return true }
        if isPermanentWorkerError(lower) { return false }
        return lower.contains("energy")
            || lower.contains("not ready")
            || lower.contains("activate")
            || lower.contains("not activated")
            || lower.contains("not exist")
            || lower.contains("does not exist")
            || lower.contains("tronnrg")
            || lower.contains("verify")
            || lower.contains("timeout")
            || lower.contains("busy")
            || lower.contains("http")
    }

    private static func isPermanentWorkerError(_ lower: String) -> Bool {
        lower.contains("mismatch")
            || lower.contains("missing signature")
            || lower.contains("not a usdt")
            || lower.contains("not a transfer")
            || lower.contains("expired")
    }

    private static func retryWaitProgressMessage(_ lower: String) -> String {
        if lower.contains("energy") || lower.contains("not ready") {
            return "Waiting for network energy…"
        }
        if lower.contains("activate") {
            return "Activating address on Tron…"
        }
        if lower.contains("tronnrg") || lower.contains("busy") {
            return "Network provider busy — retrying…"
        }
        return "Mesh is retrying on network…"
    }

    static func nudgeWorkerContinue(obligationId: String, resumeJSON: String? = nil) async {
        guard MeshNetworkSponsorship.isRelayConfigured,
              let url = relayURL(path: "/v1/continue-queued-send")
        else { return }

        var payload: [String: Any] = ["id": obligationId]
        if let resumeJSON,
           let data = resumeJSON.data(using: .utf8),
           let resumeBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            for (key, value) in resumeBody where key != "id" {
                payload[key] = value
            }
        }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body
        _ = try? await MeshHTTPClient.relayData(for: request)
    }

    private static func nudgeWorkerIfStale(
        obligationId: String,
        lastNudgeAt: inout Date
    ) async {
        guard Date().timeIntervalSince(lastNudgeAt) >= 12 else { return }
        lastNudgeAt = Date()
        await nudgeWorkerContinue(obligationId: obligationId)
    }

    /// True when the first private hop is on-chain (safe to leave handoff).
    private static func workerNetworkHasStarted(_ status: SendStatusResponse) -> Bool {
        if status.isPrivateSend == true {
            let step = status.currentStepIndex ?? 0
            if step >= 1 { return true }
            if let stepTx = status.lastStepTxID, !stepTx.isEmpty { return true }
            return false
        }

        if let started = status.networkStartedAtMs, started > 0 { return true }
        if status.status == "processing_queue" { return true }
        return false
    }

    private static func workerProgressMessage(from status: SendStatusResponse, started: Bool) -> String {
        guard status.isPrivateSend == true else {
            return started ? "Mesh started sending on network…" : "Sending on network…"
        }

        let total = max(status.totalSteps ?? 0, 1)
        let step = min(max((status.currentStepIndex ?? 0) + 1, 1), total)
        if let label = status.lastStepLabel, !label.isEmpty {
            return "Private route step \(step)/\(total) (\(label))…"
        }
        return "Private route step \(step)/\(total)…"
    }

    static func clearDelinquent(userAddress: String, obligationId: String?) async {
        guard MeshNetworkSponsorship.isRelayConfigured,
              let url = relayURL(path: "/v1/clear-wallet-delinquent")
        else { return }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["userAddress": userAddress]
        if let obligationId, !obligationId.isEmpty {
            body["obligationId"] = obligationId
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data
        _ = try? await MeshHTTPClient.relayData(for: request)
    }

    private static func relayDataWithRateLimitRetry(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await MeshHTTPClient.relayData(for: request)
    }
}
