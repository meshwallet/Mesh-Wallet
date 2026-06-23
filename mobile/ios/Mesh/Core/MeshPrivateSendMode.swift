import Foundation

/// How many intermediate relay wallets to use before the recipient (when private send is on).
enum MeshPrivateSendMode: String, CaseIterable, Identifiable {
    case standard

    /// Upper bound for relay hops in `MeshPrivacyRelayService`.
    static let maximumRelayHops = 1

    var id: String { rawValue }

    var relayHopCount: Int {
        1
    }

    var title: String {
        L10n.Send.methodPrivate
    }

    var subtitle: String {
        L10n.Send.methodPrivateHops
    }

    var estimatedMinutes: String {
        L10n.Send.timingPrivate
    }
}
