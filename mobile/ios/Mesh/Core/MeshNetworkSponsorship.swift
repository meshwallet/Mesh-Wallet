import Foundation

/// When enabled, Mesh pays Tron network costs; the app never surfaces TRX to the user.
enum MeshNetworkSponsorship {
    static var isEnabled: Bool { true }

    /// Base URL for the sponsorship relay (Cloudflare Worker). See `mesh-sponsorship-worker/`.
    static var relayBaseURL: URL? {
        let plist = Bundle.main.object(forInfoDictionaryKey: "MESH_SPONSORSHIP_RELAY_URL") as? String
        let trimmed = plist?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty, let url = URL(string: trimmed) { return url }

        let env = ProcessInfo.processInfo.environment["MESH_SPONSORSHIP_RELAY_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty, let url = URL(string: env) { return url }

        return nil
    }

    static var isRelayConfigured: Bool { relayBaseURL != nil }

    /// Optional `Authorization: Bearer` for the sponsorship worker (`RELAY_AUTH_SECRET` on worker).
    static var relayAuthSecret: String? {
        let plist = Bundle.main.object(forInfoDictionaryKey: "MESH_RELAY_AUTH_SECRET") as? String
        let trimmed = plist?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return ProcessInfo.processInfo.environment["MESH_RELAY_AUTH_SECRET"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
