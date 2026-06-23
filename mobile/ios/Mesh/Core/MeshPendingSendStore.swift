import Foundation

/// Persisted in-flight / recent sends so they survive app restarts.
struct PendingSendRecord: Codable, Identifiable {
    enum Status: String, Codable {
        case processing
        case confirmed
        case failed
    }

    let id: String
    let walletID: String
    let recipientAddress: String
    let amountText: String
    let amountUSDT: String
    let isPrivateSendMode: Bool
    let sendPrivacyMode: String
    var stepMessage: String
    let startedAt: Date
    var txID: String
    let fromAddress: String
    let toAddress: String
    let dayLabel: String
    let timestamp: Date
    var status: Status
    var failedMessage: String?
    var networkFeeCollected: Bool?
    /// Worker broadcasts pre-signed txs after handoff (app may close).
    var workerQueued: Bool?
    /// Worker accepted signed txs via register-send-fee (do not sign/register again).
    var handoffRegistered: Bool?
    /// Pre-signed user→treasury fee tx (24h); used if worker fee step is missed.
    var presignedFeeTxJSON: String?
    /// Register payload for worker retry when KV quota blocks send status polling.
    var handoffResumeJSON: String?
    /// Receive-slot index locked when the send was confirmed (0 = Address 1).
    var selectedSendSlotIndex: UInt32?
    /// On-chain USDT for the spend address when the send started (avoids double hold after broadcast).
    var chainUSDTAtStart: String?

    var hasCollectedNetworkFee: Bool { networkFeeCollected ?? false }
    var isWorkerQueued: Bool { workerQueued ?? false }
    var isHandoffRegistered: Bool { handoffRegistered ?? false }
}

enum MeshPendingSendStore {
    private static let storageKey = "mesh.pendingSends.v1"

    static func load() -> [PendingSendRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingSendRecord].self, from: data)) ?? []
    }

    static func save(_ records: [PendingSendRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func upsert(_ record: PendingSendRecord) {
        var all = load()
        all.removeAll { $0.id == record.id }
        all.append(record)
        save(all)
    }

    static func remove(id: String) {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
    }
}
