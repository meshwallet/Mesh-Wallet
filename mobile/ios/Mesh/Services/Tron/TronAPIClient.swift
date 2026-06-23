import Foundation

enum TronAPIClient {
    static func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await request(method: "GET", path: path, query: query, body: nil)
    }

    static func post(path: String, jsonBody: [String: Any]? = nil) async throws -> Data {
        var bodyData: Data?
        if let jsonBody {
            bodyData = try JSONSerialization.data(withJSONObject: jsonBody)
        } else {
            bodyData = Data("{}".utf8)
        }
        return try await request(method: "POST", path: path, query: [], body: bodyData, contentType: "application/json")
    }

    private static let rateLimitBackoffNs: [UInt64] = [
        0,
        600_000_000,
        1_500_000_000,
        3_000_000_000,
        6_000_000_000,
    ]

    private static func request(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        contentType: String? = nil
    ) async throws -> Data {
        var lastRateLimited: TronAPIError?

        for delayNs in rateLimitBackoffNs {
            if delayNs > 0 {
                try await Task.sleep(nanoseconds: delayNs)
            }
            do {
                return try await performRequestOnce(
                    method: method,
                    path: path,
                    query: query,
                    body: body,
                    contentType: contentType
                )
            } catch let error as TronAPIError {
                if case .rateLimited = error {
                    lastRateLimited = error
                    continue
                }
                throw error
            }
        }

        throw lastRateLimited ?? .rateLimited
    }

    private static func performRequestOnce(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        contentType: String? = nil
    ) async throws -> Data {
        guard var components = URLComponents(string: TronConfiguration.tronGridBaseURL + path) else {
            throw TronAPIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw TronAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let keys = TronGridKeyPool.keysForRequest()
        var lastRateLimited: TronAPIError?

        if keys.isEmpty {
            let (data, response) = try await MeshHTTPClient.apiData(for: request)
            return try parseResponse(data: data, response: response, apiKey: nil)
        }

        for apiKey in keys {
            var keyedRequest = request
            TronGridKeyPool.applyKey(apiKey, to: &keyedRequest)

            let (data, response) = try await MeshHTTPClient.apiData(for: keyedRequest)
            do {
                return try parseResponse(data: data, response: response, apiKey: apiKey)
            } catch let error as TronAPIError {
                if case .rateLimited = error {
                    TronGridKeyPool.markRateLimited(apiKey)
                    lastRateLimited = error
                    continue
                }
                throw error
            }
        }

        throw lastRateLimited ?? .rateLimited
    }

    private static func parseResponse(
        data: Data,
        response: URLResponse,
        apiKey: String?
    ) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw TronAPIError.decodingFailed
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        switch http.statusCode {
        case 200...299:
            return data
        case 403, 429:
            if let apiKey {
                TronGridKeyPool.markRateLimited(apiKey)
            }
            throw TronAPIError.rateLimited
        default:
            throw TronAPIError.httpStatus(http.statusCode, bodyText)
        }
    }
}
