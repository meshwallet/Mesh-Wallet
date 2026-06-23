import Foundation

enum MeshHTTPClient {
    private static let relaySession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static let apiSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func relayData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let backoffNs: [UInt64] = [0, 900_000_000, 2_200_000_000, 5_000_000_000]
        var lastRateLimited: (Data, URLResponse)?

        for delayNs in backoffNs {
            if delayNs > 0 {
                try await Task.sleep(nanoseconds: delayNs)
            }
            let (data, response) = try await data(for: request, session: relaySession, retries: 2)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                lastRateLimited = (data, response)
                continue
            }
            return (data, response)
        }

        if let lastRateLimited {
            return lastRateLimited
        }
        return try await data(for: request, session: relaySession, retries: 2)
    }

    static func apiData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, session: apiSession, retries: 1)
    }

    private static func data(
        for request: URLRequest,
        session: URLSession,
        retries: Int
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?
        let attempts = max(1, retries + 1)

        for attempt in 0..<attempts {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                guard attempt < attempts - 1, shouldRetry(error) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

extension Error {
    /// Pull-to-refresh dismissal, task replacement, etc. — not a user-visible failure.
    var isTransientCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

enum SendErrorPresenter {
    static let rateLimitUserMessage =
        "Tron network is busy. Please wait about a minute and try again."

    static func containsRateLimitSignal(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("429")
            || lower.contains("rate limit")
            || lower.contains("too many requests")
            || lower.contains("too many subrequests")
    }

    /// Relay / Tron hiccups during send review prep — retry in the background instead of surfacing HTTP details.
    static func isTransientRelayPrepError(_ error: Error) -> Bool {
        if isTransientNetworkError(error) { return true }
        if error is CancellationError { return true }
        return isTransientRelayPrepMessage(message(for: error))
    }

    static func isTransientRelayPrepMessage(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return true }
        if containsRateLimitSignal(lower) { return true }
        if lower.contains("http 5") || lower.contains("http 429") { return true }
        if lower.contains("temporarily unavailable") { return true }
        if lower.contains("network is busy") { return true }
        if lower.contains("hit an error") { return true }
        if lower.contains("mesh send service") && lower.contains("try again") { return true }
        if lower.contains("energy")
            || lower.contains("bandwidth")
            || lower.contains("resource insufficient")
            || lower.contains("account resource")
        {
            return true
        }
        return false
    }

    /// Connection drops when the app backgrounds or the relay times out — not a final send failure.
    static func isTransientNetworkError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .timedOut,
                 .cancelled:
                return true
            default:
                break
            }
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("connection was lost")
            || text.contains("internet connection appears to be offline")
            || text.contains("network connection was lost")
    }

    static func detailedMessage(for error: Error, stage: String? = nil) -> String {
        let core = message(for: error)
        guard let stage = normalizedStage(stage), !stage.isEmpty else { return core }
        if core.lowercased().hasPrefix(stage.lowercased()) { return core }
        return "\(stage): \(core)"
    }

    private static func normalizedStage(_ stage: String?) -> String? {
        guard let stage else { return nil }
        let trimmed = stage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "Processing",
              trimmed != "Starting…",
              trimmed != L10n.Send.processing
        else { return nil }
        return trimmed
    }

    static func message(for error: Error) -> String {
        if error is CancellationError {
            return "Send was cancelled."
        }
        if let tron = error as? TronAPIError {
            return userFacingRelayText(tron.localizedDescription ?? tron.errorDescription ?? "Send failed.")
        }
        if error.localizedDescription.lowercased().contains("429") {
            return rateLimitUserMessage
        }
        if let urlError = error as? URLError {
            return relayReachabilityMessage(urlError)
        }
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("connection was lost") {
            return "The connection dropped during this send. Check your connection and try again."
        }
        return userFacingRelayText(text)
    }

    static func relayReachabilityMessage(
        _ urlError: URLError,
        endpoint: String? = nil
    ) -> String {
        let detail = urlErrorDetail(urlError)
        let host = urlError.failingURL?.host?.lowercased() ?? ""
        let service: String
        if host.contains("workers.dev") || host.contains("meshwallet") {
            service = "Mesh send service"
        } else if host.contains("trongrid.io") {
            service = "Tron network"
        } else {
            service = "Network"
        }

        var message = "\(service) — \(detail)"
        if let endpoint, !endpoint.isEmpty {
            message += " while calling \(endpoint)"
        } else if !host.isEmpty {
            message += " (\(host))"
        }
        message += "."
        return message
    }

    private static func urlErrorDetail(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "no internet connection"
        case .networkConnectionLost:
            return "connection was lost (often happens if the app was backgrounded)"
        case .cannotConnectToHost:
            return "could not connect to the server"
        case .dnsLookupFailed:
            return "could not resolve the server address"
        case .timedOut:
            return "the server did not respond in time"
        case .cancelled:
            return "request was cancelled"
        case .secureConnectionFailed:
            return "secure connection failed"
        default:
            let label = error.code.rawValue
            let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if description.isEmpty {
                return "network error \(label)"
            }
            return description
        }
    }

    /// Turns relay JSON bodies like `{"ok":false,"message":"feeUSDT invalid"}` into readable copy.
    static func userFacingRelayText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Mesh send service is temporarily unavailable. Please try again."
        }

        if isHTMLPayload(trimmed) {
            return htmlPayloadMessage(trimmed)
        }

        if containsRateLimitSignal(trimmed) {
            return rateLimitUserMessage
        }

        if trimmed.count > 240, !trimmed.hasPrefix("{") {
            return trimmed
        }

        if trimmed.count > 240 {
            return "Mesh send service is temporarily unavailable. Please try again."
        }

        if let kvMessage = kvWriteLimitMessage(trimmed) {
            return kvMessage
        }

        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String,
              !message.isEmpty
        else {
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                return "Mesh send service rejected the request. Please try again."
            }
            return trimmed
        }
        switch message {
        case "feeUSDT invalid":
            return "Send service rejected the request. Please try again."
        default:
            if let kvMessage = kvWriteLimitMessage(message) {
                return kvMessage
            }
            if containsRateLimitSignal(message) {
                return rateLimitUserMessage
            }
            if message.localizedCaseInsensitiveContains("from-address mismatch") {
                return "Send could not start because the spending address did not match. Please try again."
            }
            return message
        }
    }

    static func relayFailureMessage(
        data: Data,
        httpStatus: Int? = nil,
        fallback: String = "Could not reach send service",
        endpoint: String? = nil
    ) -> String {
        if httpStatus == 429 {
            return rateLimitUserMessage
        }
        let raw = String(data: data, encoding: .utf8) ?? fallback
        if let httpStatus, !(200...299).contains(httpStatus), isHTMLPayload(raw) {
            let html = htmlPayloadMessage(raw)
            if let endpoint, !endpoint.isEmpty {
                return "Mesh send service HTTP \(httpStatus) on \(endpoint) — \(html)"
            }
            return "Mesh send service HTTP \(httpStatus) — \(html)"
        }
        let message = userFacingRelayText(raw)
        if let httpStatus, !(200...299).contains(httpStatus) {
            if message != raw, !message.isEmpty {
                return "Mesh send service HTTP \(httpStatus) — \(message)"
            }
            return "Mesh send service HTTP \(httpStatus) — \(fallback)."
        }
        if let endpoint, !endpoint.isEmpty, message != raw {
            return "\(endpoint): \(message)"
        }
        return message
    }

    private static func isHTMLPayload(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<!doctype html")
            || lower.contains("<html")
            || lower.contains("<head>")
            || lower.contains("worker threw exception")
            || lower.contains("cloudflare")
    }

    private static func htmlPayloadMessage(_ html: String) -> String {
        let lower = html.lowercased()
        if lower.contains("worker threw exception") {
            return "Mesh send service hit an error. Please try again in a few minutes."
        }
        return "Mesh send service is temporarily unavailable. Please try again."
    }

    private static func kvWriteLimitMessage(_ text: String) -> String? {
        let lower = text.lowercased()
        guard lower.contains("kv put") && lower.contains("limit exceeded") else {
            return nil
        }
        return "Mesh send service is at capacity for today. Please try again tomorrow."
    }
}
