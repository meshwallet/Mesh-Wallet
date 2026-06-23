import Combine
import Foundation

/// Privacy deep recovery — continues after Wallet Privacy is closed.
@MainActor
final class MeshDeepRecoveryService: ObservableObject {
    static let shared = MeshDeepRecoveryService()

    @Published private(set) var isRunning = false
    @Published private(set) var progressChecked = 0
    @Published private(set) var progressTotal = Int(MeshPrivacyStore.deepRecoveryScanAddressCount)
    @Published private(set) var isTransferring = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private var recoveryTask: Task<Void, Never>?

    private init() {}

    var progressFraction: Double {
        guard progressTotal > 0 else { return 0 }
        return min(1, Double(progressChecked) / Double(progressTotal))
    }

    func start(walletID: String? = MeshWalletRegistry.activeWalletID) {
        guard !isRunning else { return }

        isRunning = true
        errorMessage = nil
        statusMessage = nil
        isTransferring = false
        progressChecked = 0
        progressTotal = Int(MeshPrivacyStore.deepRecoveryScanAddressCount)

        recoveryTask = Task(priority: .userInitiated) { @MainActor in
            await run(walletID: walletID)
        }
    }

    func cancel() {
        recoveryTask?.cancel()
        recoveryTask = nil
        isRunning = false
        isTransferring = false
    }

    private func run(walletID: String?) async {
        defer {
            isRunning = false
            isTransferring = false
            recoveryTask = nil
        }

        do {
            let count = try await MeshPrivacyService.recoverDeepFundsToMainWallet(
                walletID: walletID
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.apply(progress)
                }
            }
            statusMessage = L10n.Send.deepRecoveryDone(count)
            errorMessage = nil
            NotificationCenter.default.post(name: .meshWalletBalancesShouldRefresh, object: nil)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            statusMessage = nil
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            if MeshPrivacyService.isRateLimitError(error) {
                errorMessage = L10n.Send.deepRecoveryRateLimited
            } else {
                errorMessage = SendErrorPresenter.message(for: error)
            }
            statusMessage = nil
        }
    }

    private func apply(_ progress: MeshPrivacyService.DeepRecoveryProgress) {
        switch progress {
        case let .scanning(checked, total):
            isTransferring = false
            progressChecked = checked
            progressTotal = total
        case let .transferring(current, total):
            isTransferring = true
            progressChecked = current
            progressTotal = total
        }
    }
}
