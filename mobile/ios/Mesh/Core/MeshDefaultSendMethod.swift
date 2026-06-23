import Foundation

/// Default send method chosen in Wallet privacy; applied when opening Send.
enum MeshDefaultSendMethod: String, CaseIterable, Identifiable {
    case direct
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct:
            return L10n.Send.methodDirect
        case .standard:
            return L10n.Send.methodPrivate
        }
    }

    var privateSendMode: MeshPrivateSendMode? {
        switch self {
        case .direct: return nil
        case .standard: return .standard
        }
    }

    var isPrivateSend: Bool {
        self != .direct
    }

    var fee: Decimal {
        switch self {
        case .direct:
            return MeshSendFees.networkFee(isPrivateSend: false, mode: .standard)
        case .standard:
            return MeshSendFees.networkFee(isPrivateSend: true, mode: .standard)
        }
    }

    var timing: String {
        switch self {
        case .direct:
            return L10n.Send.timingDirect
        case .standard:
            return MeshPrivateSendMode.standard.estimatedMinutes
        }
    }

    var detail: String {
        switch self {
        case .direct:
            return L10n.Send.methodDirectDetail
        case .standard:
            return L10n.Send.methodPrivateDetail
        }
    }
}
