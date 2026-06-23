import Foundation

/// Biometric gate for sensitive actions (backup, etc.), with passcode sheet fallback.
@MainActor
enum MeshSensitiveAuth {
    static var canUseBiometric: Bool {
        MeshPasscodeStore.isEnabled
            && MeshPasscodeStore.isBiometricEnabled
            && MeshBiometricAuth.isAvailable
    }

    /// Tries Face ID / Touch ID when enabled; otherwise calls `onNeedPasscode`.
    static func authenticate(
        reason: String,
        onSuccess: @escaping () -> Void,
        onNeedPasscode: @escaping () -> Void
    ) async {
        guard MeshPasscodeStore.isEnabled else {
            onNeedPasscode()
            return
        }
        guard canUseBiometric else {
            onNeedPasscode()
            return
        }

        let result = await MeshBiometricAuth.authenticate(reason: reason)
        if result == .success {
            onSuccess()
        } else {
            onNeedPasscode()
        }
    }
}
