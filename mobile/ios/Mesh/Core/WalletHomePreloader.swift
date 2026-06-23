import Foundation

/// Warms wallet home data behind the launch passcode so unlock does not mount + fetch in one frame.
@MainActor
enum WalletHomePreloader {
    static let viewModel = WalletHomeViewModel()

    private static var warmTask: Task<Void, Never>?
    private static var warmingWalletID: String?
    private(set) static var warmedWalletID: String?

    static func matchesWarmedWallet(_ walletID: String) -> Bool {
        warmedWalletID == walletID && warmTask == nil
    }

    static func awaitWarmIfNeeded() async {
        await warmTask?.value
    }

    static func startWarmIfNeeded() {
        guard WalletSession.hasActiveWallet,
              let walletID = MeshWalletRegistry.activeWalletID
        else { return }

        if matchesWarmedWallet(walletID) { return }
        if warmTask != nil, warmingWalletID == walletID { return }

        warmTask?.cancel()
        warmedWalletID = nil
        warmingWalletID = walletID
        warmTask = Task(priority: .utility) {
            await Task.yield()
            viewModel.prepareForWallet(id: walletID)
            await viewModel.load(transactionLimit: 24)
            guard !Task.isCancelled else { return }
            warmedWalletID = walletID
            warmingWalletID = nil
            warmTask = nil
        }
    }

    static func invalidate(forWalletID walletID: String? = nil) {
        if let walletID,
           warmedWalletID != walletID,
           warmingWalletID != walletID
        {
            return
        }
        warmTask?.cancel()
        warmTask = nil
        warmingWalletID = nil
        warmedWalletID = nil
    }
}
