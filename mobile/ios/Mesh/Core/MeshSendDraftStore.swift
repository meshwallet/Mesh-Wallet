import Combine
import Foundation

/// Keeps in-progress send forms alive while the send modal is closed (per wallet).
@MainActor
enum MeshSendDraftStore {
    private static var modelsByWalletID: [String: SendFlowViewModel] = [:]

    static func model(walletID: String) -> SendFlowViewModel {
        if let existing = modelsByWalletID[walletID] {
            return existing
        }
        let created = SendFlowViewModel()
        modelsByWalletID[walletID] = created
        return created
    }

    static func drop(walletID: String) {
        modelsByWalletID.removeValue(forKey: walletID)
    }
}

/// Home-level holder so SwiftUI observes the active wallet's send draft.
@MainActor
final class SendFlowBinding: ObservableObject {
    @Published private(set) var model: SendFlowViewModel
    private var boundWalletID: String

    init() {
        let walletID = MeshWalletRegistry.activeWalletID ?? WalletAccountStore.mainWalletID
        boundWalletID = walletID
        model = MeshSendDraftStore.model(walletID: walletID)
    }

    func bind(walletID: String) {
        guard walletID != boundWalletID else { return }
        boundWalletID = walletID
        model = MeshSendDraftStore.model(walletID: walletID)
    }

    func refreshAfterDraftCleared(walletID: String) {
        boundWalletID = walletID
        model = MeshSendDraftStore.model(walletID: walletID)
    }
}
