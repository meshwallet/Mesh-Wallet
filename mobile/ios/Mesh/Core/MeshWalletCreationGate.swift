import Foundation

/// Survives SwiftUI view recreation during wallet create / restore handoff.
enum MeshWalletCreationGate {
    enum Phase: Equatable {
        case idle
        case generated(PendingWalletDraft)
        case committed(String)
    }

    private static let lock = NSLock()
    private static var phase: Phase = .idle
    private static var generationInFlight = false
    private static var commitInFlightAddress: String?

    static var hasCommitted: Bool {
        withLock {
            if case .committed = phase { return true }
            return false
        }
    }

    static var storedDraft: PendingWalletDraft? {
        withLock {
            if case .generated(let draft) = phase { return draft }
            return nil
        }
    }

    static func reset() {
        withLock {
            phase = .idle
            generationInFlight = false
            commitInFlightAddress = nil
        }
    }

    /// Only one `generateWallet()` at a time, even if SwiftUI recreates the flow view.
    static func tryBeginGeneration() -> Bool {
        withLock {
            if generationInFlight { return false }
            switch phase {
            case .idle:
                generationInFlight = true
                return true
            case .generated, .committed:
                return false
            }
        }
    }

    static func abortGeneration() {
        withLock {
            generationInFlight = false
        }
    }

    /// Reuse or capture the single draft for this flow.
    static func captureDraft(_ draft: PendingWalletDraft) -> Bool {
        withLock {
            generationInFlight = false
            switch phase {
            case .idle:
                phase = .generated(draft)
                return true
            case .generated(let existing):
                return existing == draft
            case .committed(let address):
                return address == normalize(draft.address)
            }
        }
    }

    /// Allow one new registration per flow (idempotent for the same address).
    static func tryCommitAddress(_ address: String) -> Bool {
        let normalized = normalize(address)
        guard !normalized.isEmpty else { return false }
        return withLock {
            switch phase {
            case .idle:
                return false
            case .generated(let draft):
                guard draft.address == normalized else { return false }
                phase = .committed(normalized)
                return true
            case .committed(let committed):
                return committed == normalized
            }
        }
    }

    /// Only one `activateWallet()` at a time per address (parallel SwiftUI hosts).
    static func tryBeginCommit(for address: String) -> Bool {
        let normalized = normalize(address)
        guard !normalized.isEmpty else { return false }
        return withLock {
            if let inFlight = commitInFlightAddress {
                return inFlight == normalized
            }
            commitInFlightAddress = normalized
            return true
        }
    }

    static func finishCommit() {
        withLock {
            commitInFlightAddress = nil
        }
    }

    /// Registry last resort — block a second *different* wallet during one flow.
    static func allowsRegistryInsert(for address: String) -> Bool {
        let normalized = normalize(address)
        guard !normalized.isEmpty else { return false }
        return withLock {
            switch phase {
            case .idle:
                return true
            case .generated(let draft):
                return draft.address == normalized
            case .committed(let committed):
                return committed == normalized
            }
        }
    }

    private static func normalize(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
