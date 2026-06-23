import Foundation

/// Limits concurrent TronGrid calls to avoid HTTP 429.
actor TronGridRequestGate {
    static let wallet = TronGridRequestGate(maxConcurrent: 2)
    static let deepRecovery = TronGridRequestGate(maxConcurrent: 3)

    private let maxConcurrent: Int
    private var inFlight = 0

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func perform<T>(_ operation: () async throws -> T) async throws -> T {
        while inFlight >= maxConcurrent {
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        inFlight += 1
        defer { inFlight -= 1 }
        return try await operation()
    }
}
