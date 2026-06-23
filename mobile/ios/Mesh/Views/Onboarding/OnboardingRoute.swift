import Foundation

enum OnboardingRoute: Hashable {
    case welcome
    case addExistingWallet
    case restorePhrase
    case createLaunch
    case setupPasscode(PendingWalletDraft)
    case confirmPasscode(draft: String, pending: PendingWalletDraft)
    case faceIDSetup
    case walletReady
    case restorePrivateKey
}
