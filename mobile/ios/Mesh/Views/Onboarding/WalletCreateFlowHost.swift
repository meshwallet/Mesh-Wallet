import Combine
import SwiftUI

/// Holds create-flow state outside modal hosting so SwiftUI resets do not re-generate wallets.
@MainActor
final class WalletCreateFlowModel: ObservableObject {
    @Published private(set) var didStart = false

    func markStarted() {
        didStart = true
    }

    func reset() {
        didStart = false
    }
}

struct WalletCreateFlowHost: View {
    @ObservedObject var flowModel: WalletCreateFlowModel
    let onFinished: () -> Void
    let onCancel: () -> Void

    var body: some View {
        OnboardingFlowView(
            startPoint: .create,
            createFlowModel: flowModel,
            onFinished: {
                MeshWalletCreationGate.reset()
                flowModel.reset()
                onFinished()
            },
            onCancelFromRoot: {
                MeshWalletCreationGate.reset()
                flowModel.reset()
                onCancel()
            }
        )
    }
}
