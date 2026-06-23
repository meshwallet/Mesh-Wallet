import Foundation

struct WalletAccount: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let address: String
}

enum WalletAccountStore {
    static let mainWalletID = "main"

    static func activeAccounts() -> [WalletAccount] {
        MeshWalletRegistry.wallets.map { wallet in
            let subtitle = wallet.address.isEmpty
                ? "Tron · USDT"
                : "Tron · \(TronUSDTService.shortAddress(wallet.address))"
            return WalletAccount(
                id: wallet.id,
                name: wallet.name,
                subtitle: subtitle,
                address: wallet.address
            )
        }
    }

    static func activeAccountName() -> String {
        guard let id = MeshWalletRegistry.activeWalletID,
              let wallet = MeshWalletRegistry.wallet(id: id)
        else {
            return activeAccounts().first?.name ?? "Main wallet"
        }
        return wallet.name
    }
}
