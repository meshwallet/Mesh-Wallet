import Foundation

/// Requests Energy delegation for a sender address before broadcasting (Mesh-operated relay).
enum MeshEnergyBrokerService {
    enum ActivationPrepStatus {
        case submitting
        case retrying
        case waitingConfirmation
    }

    enum NetworkPrepStatus {
        case preparing
        case requestingEnergy
        case waitingEnergy
        case waitingResources
        case preparingBandwidth
        case waitingBandwidth
        case retrying
    }

    struct PrepareResponse: Decodable {
        let ok: Bool
        let message: String?
        let activations: [ActivationRecord]?
        let energy: Int?
    }

    struct ActivationRecord: Decodable {
        let address: String
        let tx: String
    }

    private struct ActivateResponse: Decodable {
        let ok: Bool
        let message: String?
    }

    /// Activates a fresh receive address (or private-send relay) on Tron via the Mesh worker.
    static func activateTronAddress(
        _ address: String,
        statusUpdate: ((ActivationPrepStatus) -> Void)? = nil
    ) async throws {
        guard MeshNetworkSponsorship.isEnabled else { return }

        var lastError: Error?
        for attempt in 0..<4 {
            statusUpdate?(attempt == 0 ? .submitting : .retrying)
            do {
                try await activateTronAddressOnce(address)
                return
            } catch {
                lastError = error
                guard attempt < 3, isActivationError(error) else { throw error }
                try await Task.sleep(nanoseconds: 12_000_000_000)
            }
        }
        throw lastError ?? TronAPIError.broadcastFailed("Activation failed.")
    }

    /// Ensures a **Mesh-owned** address (user sender, relay hop, receive slot) exists on Tron.
    static func ensureActivatedOnTron(
        _ address: String,
        statusUpdate: ((String) -> Void)? = nil
    ) async throws {
        guard MeshNetworkSponsorship.isEnabled else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !(await TronAPIService.isAccountActivated(address: trimmed)) else { return }
        statusUpdate?("Activating address on Tron…")
        try await activateTronAddress(trimmed)
    }

    /// Polls Tron until an address is activated or the timeout elapses.
    static func waitForAccountActivated(
        _ address: String,
        timeoutSeconds: Int = 120,
        pollIntervalSeconds: Double = 2,
        statusUpdate: ((ActivationPrepStatus) -> Void)? = nil
    ) async -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        statusUpdate?(.waitingConfirmation)
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if await TronAPIService.isAccountActivated(address: trimmed) {
                return true
            }
            statusUpdate?(.waitingConfirmation)
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
        }
        return await TronAPIService.isAccountActivated(address: trimmed)
    }

    private static func isActivationError(_ error: Error) -> Bool {
        if SendErrorPresenter.isTransientRelayPrepError(error) { return true }
        let text: String
        if let tron = error as? TronAPIError, case .broadcastFailed(let reason) = tron {
            text = reason
        } else {
            text = error.localizedDescription
        }
        let lower = text.lowercased()
        return lower.contains("activate") || lower.contains("activating")
    }

    private static func activateTronAddressOnce(_ address: String) async throws {
        guard let base = MeshNetworkSponsorship.relayBaseURL else {
            throw TronAPIError.broadcastFailed("Send service is temporarily unavailable.")
        }
        guard let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/activate") else {
            throw TronAPIError.broadcastFailed("Send service URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 50
        if let secret = MeshNetworkSponsorship.relayAuthSecret {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["address": address])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await MeshHTTPClient.relayData(for: request)
        } catch let urlError as URLError {
            throw TronAPIError.broadcastFailed(
                SendErrorPresenter.relayReachabilityMessage(urlError, endpoint: "activate")
            )
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw TronAPIError.broadcastFailed(
                SendErrorPresenter.relayFailureMessage(
                    data: data,
                    httpStatus: status,
                    fallback: "activate failed",
                    endpoint: "activate"
                )
            )
        }
        let decoded = try JSONDecoder().decode(ActivateResponse.self, from: data)
        guard decoded.ok else {
            throw TronAPIError.broadcastFailed(decoded.message ?? "Activation failed")
        }
    }

    /// Typical TRC-20 transfer (~65k). Used for direct sends.
    private static let preferredEnergy: Int64 = 65_000
    static var preferredTransferEnergy: Int64 { preferredEnergy }
    /// New / empty recipients need ~130k Energy on Tron (matches worker HIGH_ENERGY_TARGET).
    private static let highEnergyMinimum: Int64 = 120_000
    /// Matches worker standard tier (treasury / fee transfers).
    private static let standardEnergyMinimum: Int64 = 28_000

    static func energyMinimum(for highEnergy: Bool) -> Int64 {
        highEnergy ? highEnergyMinimum : standardEnergyMinimum
    }

    /// Requests energy in the background while the user reviews the send (does not block broadcast).
    static func requestSenderEnergyInBackground(
        address: String,
        toAddress: String,
        highEnergy: Bool = false
    ) {
        guard MeshNetworkSponsorship.isEnabled else { return }
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return }
        let destination = trimmedTo.isEmpty ? trimmedAddress : trimmedTo
        Task.detached(priority: .utility) {
            _ = try? await prepareSenderOnce(
                address: trimmedAddress,
                toAddress: destination,
                highEnergy: highEnergy,
                skipRecipientActivation: true
            )
        }
    }

    /// One relay call — no sleeps (used before a broadcast retry).
    static func prepareSenderFast(
        address: String,
        toAddress: String,
        highEnergy: Bool = false
    ) async throws {
        guard MeshNetworkSponsorship.isEnabled else { return }
        _ = try await prepareSenderOnce(
            address: address,
            toAddress: toAddress,
            highEnergy: highEnergy,
            skipRecipientActivation: true
        )
    }

    /// Fast when relay energy is already on the sender; otherwise delegates and polls until ready.
    static func ensureSenderReadyForBroadcast(
        address: String,
        toAddress: String,
        highEnergy: Bool = false,
        timeoutSeconds: Int = 90,
        energyMinimumOverride: Int64? = nil,
        statusUpdate: ((NetworkPrepStatus) -> Void)? = nil
    ) async throws {
        guard MeshNetworkSponsorship.isEnabled else { return }
        let energyFloor = energyMinimumOverride ?? energyMinimum(for: highEnergy)
        if await hasTransferEnergy(address: address, minimum: energyFloor),
           await hasSufficientBandwidth(address: address)
        {
            return
        }
        statusUpdate?(.preparing)

        // Request energy from the relay while polling Tron — do not wait for HTTP before polling.
        let prepareTask = Task {
            statusUpdate?(.requestingEnergy)
            try await prepareSenderFast(
                address: address,
                toAddress: toAddress,
                highEnergy: highEnergy
            )
        }

        statusUpdate?(.waitingResources)
        do {
            try await requireSenderReady(
                address: address,
                highEnergy: highEnergy,
                toAddress: toAddress,
                timeoutSeconds: timeoutSeconds,
                skipInitialPrepare: true,
                energyMinimumOverride: energyMinimumOverride,
                statusUpdate: statusUpdate
            )
        } catch {
            prepareTask.cancel()
            throw error
        }

        _ = try? await prepareTask.value
    }

    /// Ensures the sender can broadcast a TRC-20 transfer without the user holding TRX.
    static func prepareSender(
        address: String,
        toAddress: String,
        highEnergy: Bool = false,
        skipRecipientActivation: Bool = true,
        statusUpdate: ((String) -> Void)? = nil
    ) async throws {
        guard MeshNetworkSponsorship.isEnabled else { return }

        let tierMinimum = energyMinimum(for: highEnergy)
        var lastError: Error?

        for attempt in 0..<3 {
            if attempt > 0 {
                statusUpdate?("Mesh is retrying network preparation…")
                try await Task.sleep(nanoseconds: UInt64(2 + attempt) * 1_000_000_000)
            }

            do {
                let delegatedEnergy = try await prepareSenderOnce(
                    address: address,
                    toAddress: toAddress,
                    highEnergy: highEnergy,
                    skipRecipientActivation: skipRecipientActivation
                )
                await settleAfterPrepare(
                    address: address,
                    delegatedEnergy: delegatedEnergy,
                    highEnergy: highEnergy
                )
                try await Task.sleep(nanoseconds: 2_000_000_000)
                lastError = nil
                break
            } catch {
                lastError = error
                let energyOK = await hasTransferEnergy(address: address, minimum: tierMinimum)
                let bandwidthOK = await hasSufficientBandwidth(address: address)
                if energyOK, bandwidthOK {
                    lastError = nil
                    break
                }
                guard attempt < 2, shouldRetryPrepare(error) else {
                    throw error
                }
            }
        }

        if let lastError {
            throw lastError
        }

        if !(await hasSufficientBandwidth(address: address)) {
            statusUpdate?("Preparing network bandwidth…")
            try await retryBandwidthPrepare(
                address: address,
                toAddress: toAddress,
                highEnergy: highEnergy
            )
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// Wait for energy after prepare; uses the tier minimum for the hop.
    static func settleAfterPrepare(
        address: String,
        delegatedEnergy: Int?,
        highEnergy: Bool
    ) async {
        let tierMinimum = energyMinimum(for: highEnergy)
        let minimumWait: UInt64
        if highEnergy {
            minimumWait = 4
        } else if let delegatedEnergy, delegatedEnergy >= 130_000 {
            minimumWait = 4
        } else if let delegatedEnergy, delegatedEnergy >= 100_000 {
            minimumWait = 3
        } else if let delegatedEnergy, delegatedEnergy >= 60_000 {
            minimumWait = 3
        } else {
            minimumWait = 2
        }
        try? await Task.sleep(nanoseconds: minimumWait * 1_000_000_000)

        let deadline = Date().addingTimeInterval(50)
        var pollNs: UInt64 = 1_000_000_000
        while Date() < deadline {
            if await hasTransferEnergy(address: address, minimum: tierMinimum) {
                return
            }
            try? await Task.sleep(nanoseconds: pollNs)
            pollNs = min(pollNs + 500_000_000, 2_500_000_000)
        }
    }

    private struct SenderReadiness {
        let energy: Int64
        let bandwidth: Int64
        let trxBalance: Double
    }

    private static func fetchSenderReadiness(address: String) async -> SenderReadiness {
        do {
            return try await TronGridRequestGate.wallet.perform {
                let resources = try? await TronAPIService.fetchAccountResources(address: address)
                let balance = await TronUSDTService.fetchBalance(address: address)
                return SenderReadiness(
                    energy: resources?.energyRemaining ?? 0,
                    bandwidth: resources?.bandwidthRemaining ?? 0,
                    trxBalance: balance.trxBalance
                )
            }
        } catch {
            return SenderReadiness(energy: 0, bandwidth: 0, trxBalance: 0)
        }
    }

    static func hasTransferEnergy(
        address: String,
        minimum: Int64 = preferredEnergy
    ) async -> Bool {
        let readiness = await fetchSenderReadiness(address: address)
        return readiness.energy >= minimum
    }

    /// True when sender still needs ops prepare (energy and/or bandwidth).
    static func needsNetworkPrepare(
        address: String,
        highEnergy: Bool
    ) async -> Bool {
        let tierMinimum = energyMinimum(for: highEnergy)
        if !(await hasTransferEnergy(address: address, minimum: tierMinimum)) {
            return true
        }
        return !(await hasSufficientBandwidth(address: address))
    }

    /// Review / send prep: ~65k Energy + bandwidth (standard USDT transfer tier).
    static func needsTransferPrep(address: String) async -> Bool {
        if !(await hasTransferEnergy(address: address)) {
            return true
        }
        return !(await hasSufficientBandwidth(address: address))
    }

    private static let minimumBandwidth: Int64 = 400
    /// Matches worker `BANDWIDTH_TOPUP_TRX_SUN` (3 TRX) with a small margin.
    private static let minimumTRXForBandwidthBurn: Double = 2.8

    static func hasSufficientBandwidth(address: String) async -> Bool {
        let readiness = await fetchSenderReadiness(address: address)
        return readiness.bandwidth >= minimumBandwidth
            || readiness.trxBalance >= minimumTRXForBandwidthBurn
    }

    /// Blocks until sender has Energy and bandwidth (or TRX to burn) before broadcast.
    static func requireSenderReady(
        address: String,
        highEnergy: Bool,
        toAddress: String? = nil,
        timeoutSeconds: Int = 90,
        skipInitialPrepare: Bool = false,
        energyMinimumOverride: Int64? = nil,
        statusUpdate: ((NetworkPrepStatus) -> Void)? = nil
    ) async throws {
        let energyMinimum = energyMinimumOverride ?? energyMinimum(for: highEnergy)
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var lastEnergy: Int64 = 0
        var lastBandwidth: Int64 = 0
        var lastTRX: Double = 0
        var bandwidthPrepareAttempts = 0
        let maxBandwidthPrepareAttempts = 3
        var energyPrepareAttempts = 0
        let maxEnergyPrepareAttempts = 12
        var pollNs: UInt64 = 350_000_000
        var lastEnergyPrepareAt = Date.distantPast

        if let toAddress, !skipInitialPrepare {
            statusUpdate?(.requestingEnergy)
            try? await prepareSenderOnce(
                address: address,
                toAddress: toAddress,
                highEnergy: highEnergy,
                skipRecipientActivation: true
            )
            energyPrepareAttempts += 1
            lastEnergyPrepareAt = Date()
        }

        while Date() < deadline {
            let readiness = await fetchSenderReadiness(address: address)
            lastEnergy = readiness.energy
            lastBandwidth = readiness.bandwidth
            lastTRX = readiness.trxBalance

            let energyOK = lastEnergy >= energyMinimum
            let bandwidthOK = lastBandwidth >= minimumBandwidth || lastTRX >= minimumTRXForBandwidthBurn
            if energyOK, bandwidthOK {
                return
            }

            if !energyOK {
                statusUpdate?(.waitingEnergy)
            } else if !bandwidthOK {
                statusUpdate?(.waitingBandwidth)
            }

            if !energyOK,
               let toAddress,
               energyPrepareAttempts < maxEnergyPrepareAttempts,
               Date().timeIntervalSince(lastEnergyPrepareAt) >= 2.5
            {
                energyPrepareAttempts += 1
                lastEnergyPrepareAt = Date()
                statusUpdate?(.requestingEnergy)
                try? await prepareSenderOnce(
                    address: address,
                    toAddress: toAddress,
                    highEnergy: highEnergy,
                    skipRecipientActivation: true
                )
            }

            if energyOK,
               !bandwidthOK,
               let toAddress,
               bandwidthPrepareAttempts < maxBandwidthPrepareAttempts
            {
                bandwidthPrepareAttempts += 1
                statusUpdate?(.preparingBandwidth)
                try? await retryBandwidthPrepare(
                    address: address,
                    toAddress: toAddress,
                    highEnergy: highEnergy
                )
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }

            try await Task.sleep(nanoseconds: pollNs)
            pollNs = min(pollNs + 200_000_000, 1_500_000_000)
        }

        if lastEnergy < energyMinimum {
            throw TronAPIError.broadcastFailed(
                "Network energy was not ready yet. Wait a moment and try again."
            )
        }
        throw TronAPIError.broadcastFailed(
            "Network bandwidth was not ready yet. Wait a moment and try again."
        )
    }

    /// Re-requests worker prepare when Energy is ready but free bandwidth / TRX for burn is still low.
    private static func retryBandwidthPrepare(
        address: String,
        toAddress: String,
        highEnergy: Bool
    ) async throws {
        _ = try await prepareSenderOnce(
            address: address,
            toAddress: toAddress,
            highEnergy: highEnergy,
            skipRecipientActivation: true
        )
        try await Task.sleep(nanoseconds: 4_000_000_000)
    }

    static func isEnergyRelatedError(_ error: Error) -> Bool {
        let text: String
        if let tron = error as? TronAPIError, case .broadcastFailed(let reason) = tron {
            text = reason
        } else {
            text = error.localizedDescription
        }
        let lower = text.lowercased()
        return lower.contains("energy")
            || lower.contains("resource insufficient")
            || lower.contains("out_of_energy")
            || lower.contains("bandwidth")
    }

    @discardableResult
    private static func prepareSenderOnce(
        address: String,
        toAddress: String,
        highEnergy: Bool,
        skipRecipientActivation: Bool = true
    ) async throws -> Int? {
        guard let base = MeshNetworkSponsorship.relayBaseURL else {
            throw TronAPIError.broadcastFailed(
                "Send service is temporarily unavailable. Please try again in a few minutes."
            )
        }

        guard let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/prepare-sender") else {
            throw TronAPIError.broadcastFailed("Send service URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "application/json")
        request.timeoutInterval = 50
        if let secret = MeshNetworkSponsorship.relayAuthSecret {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "address": address,
            "toAddress": toAddress,
        ]
        if highEnergy {
            body["highEnergy"] = true
        }
        body["skipRecipientActivation"] = skipRecipientActivation
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await MeshHTTPClient.relayData(for: request)
        } catch let urlError as URLError {
            throw TronAPIError.broadcastFailed(
                SendErrorPresenter.relayReachabilityMessage(urlError, endpoint: "prepare-sender")
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw TronAPIError.broadcastFailed("prepare-sender returned an invalid response.")
        }

        guard (200...299).contains(http.statusCode) else {
            throw TronAPIError.broadcastFailed(
                SendErrorPresenter.relayFailureMessage(
                    data: data,
                    httpStatus: http.statusCode,
                    fallback: "prepare-sender failed",
                    endpoint: "prepare-sender"
                )
            )
        }

        let decoded = try JSONDecoder().decode(PrepareResponse.self, from: data)
        guard decoded.ok else {
            let detail = decoded.message ?? "prepare-sender returned ok=false"
            throw TronAPIError.broadcastFailed(
                SendErrorPresenter.userFacingRelayText(detail)
            )
        }

        return decoded.energy
    }

    private static func shouldRetryPrepare(_ error: Error) -> Bool {
        guard let tron = error as? TronAPIError,
              case .broadcastFailed(let reason) = tron
        else {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                    return true
                default:
                    return false
                }
            }
            return false
        }

        let lower = reason.lowercased()
        if lower.contains("ops wallet needs more trx") || lower.contains("relay not configured") {
            return false
        }
        return lower.contains("verify")
            || lower.contains("busy")
            || lower.contains("preparation failed")
            || lower.contains("did not activate")
            || lower.contains("activating")
            || lower.contains("http 5")
            || lower.contains("tronnrg")
            || SendErrorPresenter.containsRateLimitSignal(reason)
    }
}
