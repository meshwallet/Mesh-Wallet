import Combine
import SwiftUI

/// Passcode / Face ID only on cold app launch — not on background return or wallet switch.
@MainActor
final class AppLockController: ObservableObject {
    @Published private(set) var isUnlocked: Bool
    /// Set after a Face ID / Touch ID prompt was shown during cold launch (avoids double prompt).
    @Published private(set) var didAttemptLaunchBiometric = false

    private var didEvaluateLaunchLock = false

    init() {
        WalletSession.reconcile()
        let needsLaunchLock = MeshPasscodeStore.isEnabled && WalletSession.hasActiveWallet
        isUnlocked = !needsLaunchLock
        didEvaluateLaunchLock = needsLaunchLock
    }

    var shouldShowLock: Bool {
        MeshPasscodeStore.isEnabled && WalletSession.hasActiveWallet && !isUnlocked
    }

    /// Once per process launch (opening the app after it was terminated).
    func prepareLaunchLockIfNeeded() {
        guard !didEvaluateLaunchLock else { return }
        didEvaluateLaunchLock = true

        guard MeshPasscodeStore.isEnabled, WalletSession.hasActiveWallet else {
            isUnlocked = true
            return
        }
        isUnlocked = false
    }

    func unlock() {
        isUnlocked = true
    }

    func unlockForCurrentSession() {
        didEvaluateLaunchLock = true
        unlock()
    }

    /// Face ID / Touch ID during splash — keeps passcode UI hidden until this finishes.
    @discardableResult
    func attemptLaunchBiometricUnlock() async -> Bool {
        guard shouldShowLock else { return false }
        guard MeshPasscodeStore.isBiometricEnabled, MeshBiometricAuth.isAvailable else {
            return false
        }

        didAttemptLaunchBiometric = true
        let result = await MeshBiometricAuth.authenticate(
            reason: "Unlock Mesh"
        )
        if result == .success {
            unlock()
            return true
        }
        return false
    }
}
