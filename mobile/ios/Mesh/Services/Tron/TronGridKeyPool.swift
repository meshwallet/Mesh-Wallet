import Foundation

/// Rotates TronGrid API keys and fails over when a key hits rate limits.
enum TronGridKeyPool {
    private static let apiKeyHeader = "TRON-PRO-API-KEY"
    private static let rateLimitCooldown: TimeInterval = 45

    private static let lock = NSLock()
    private static var roundRobinIndex = 0
    private static var cooledDownUntil: [String: Date] = [:]

    static var keys: [String] {
        TronConfiguration.trongridAPIKeys
    }

    static var hasKeys: Bool {
        !keys.isEmpty
    }

    /// Keys to try for one HTTP call: round-robin first, then the rest (skipping short cooldowns).
    static func keysForRequest() -> [String] {
        let all = keys
        guard !all.isEmpty else { return [] }

        let available = all.filter { !isCooledDown($0) }
        let pool = available.isEmpty ? all : available

        lock.lock()
        let start = roundRobinIndex % pool.count
        roundRobinIndex += 1
        lock.unlock()

        var ordered: [String] = []
        for offset in 0..<pool.count {
            let key = pool[(start + offset) % pool.count]
            if !ordered.contains(key) {
                ordered.append(key)
            }
        }
        for key in all where !ordered.contains(key) {
            ordered.append(key)
        }
        return ordered
    }

    static func markRateLimited(_ key: String) {
        lock.lock()
        cooledDownUntil[key] = Date().addingTimeInterval(rateLimitCooldown)
        lock.unlock()
    }

    static func applyKey(_ key: String, to request: inout URLRequest) {
        request.setValue(key, forHTTPHeaderField: apiKeyHeader)
    }

    private static func isCooledDown(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let until = cooledDownUntil[key] else { return false }
        if until > Date() { return true }
        cooledDownUntil.removeValue(forKey: key)
        return false
    }
}
