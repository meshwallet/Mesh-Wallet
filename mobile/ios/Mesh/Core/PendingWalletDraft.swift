import Foundation

enum WalletPhraseFlow: String {
    case created
    case restored
}

enum WalletCredential: Hashable {
    case mnemonic(words: [String])
    case privateKey(hex: String)
}

/// Wallet data held in memory until passcode setup finishes.
struct PendingWalletDraft: Hashable {
    let credential: WalletCredential
    let address: String
    let walletName: String
    let flow: WalletPhraseFlow
}
