import Foundation
import LocalAuthentication

/// Biometric-only authentication. Never falls back to the iPhone system passcode —
/// on failure the app shows its own passcode screen instead.
enum MeshBiometricAuth {
    enum BiometricKind {
        case faceID
        case touchID
        case none
    }

    enum AuthResult: Equatable {
        case success
        case cancelled
        case unavailable
        case biometryLockout
        case failed
    }

    static var kind: BiometricKind {
        var error: NSError?
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID, .opticID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }

    /// Device has Face ID / Touch ID hardware (may still need enrollment in Settings).
    static var shouldOfferSetup: Bool {
        kind != .none
    }

    /// Biometrics enrolled and ready for `authenticate`.
    static var isAvailable: Bool {
        var error: NSError?
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static var setupHint: String? {
        guard shouldOfferSetup, !isAvailable else { return nil }
        return "Set up \(displayName) in iPhone Settings, then tap Enable."
    }

    static var displayName: String {
        switch kind {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .none:
            return "Biometrics"
        }
    }

    static var systemImageName: String {
        switch kind {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .none:
            return "lock.shield"
        }
    }

    @MainActor
    static func authenticate(reason: String) async -> AuthResult {
        let context = makeContext()

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return mapCanEvaluateError(error)
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, evaluateError in
                if success {
                    continuation.resume(returning: .success)
                    return
                }
                continuation.resume(returning: mapEvaluateError(evaluateError))
            }
        }
    }

    private static func makeContext() -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        // Hide "Enter Passcode" — that uses the iPhone lock screen code, not Mesh.
        context.localizedFallbackTitle = ""
        return context
    }

    private static func mapCanEvaluateError(_ error: NSError?) -> AuthResult {
        guard let laError = error as? LAError else { return .unavailable }
        switch laError.code {
        case .biometryLockout:
            return .biometryLockout
        default:
            return .unavailable
        }
    }

    private static func mapEvaluateError(_ error: Error?) -> AuthResult {
        guard let laError = error as? LAError else { return .failed }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .userFallback:
            // "Enter Passcode" on the system sheet — we ignore it; Mesh passcode is used instead.
            return .cancelled
        case .biometryLockout:
            return .biometryLockout
        case .biometryNotAvailable, .biometryNotEnrolled:
            return .unavailable
        case .authenticationFailed, .invalidContext, .notInteractive:
            return .failed
        default:
            return .failed
        }
    }
}
