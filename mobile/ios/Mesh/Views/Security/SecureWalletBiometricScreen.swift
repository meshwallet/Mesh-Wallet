import SwiftUI

struct SecureWalletBiometricScreen: View {
    let onFinished: () -> Void

    @State private var isEnabling = false
    @State private var errorMessage: String?

    private var biometricName: String {
        MeshBiometricAuth.displayName
    }

    private var canEnableNow: Bool {
        MeshBiometricAuth.isAvailable
    }

    private var subtitle: String {
        if let hint = MeshBiometricAuth.setupHint {
            return hint
        }
        if MeshBiometricAuth.shouldOfferSetup {
            return "Use \(biometricName) to unlock Mesh when you open the app."
        }
        return "Biometric unlock is not available on this device. You can use your Mesh passcode."
    }

    var body: some View {
        MeshOnboardingScreen {
            VStack(spacing: 0) {
                Spacer(minLength: 48)

                VStack(spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(MeshTheme.Colors.fieldFill)
                            .frame(width: 88, height: 88)
                        Image(systemName: MeshBiometricAuth.systemImageName)
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(MeshTheme.Colors.accent)
                    }

                    MeshTitleBlock(
                        title: "Use \(biometricName)?",
                        subtitle: subtitle,
                        centered: true
                    )
                }
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)

                if let errorMessage {
                    Text(errorMessage)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(Color.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                }

                Spacer()
            }
        } footer: {
            VStack(spacing: 16) {
                if MeshBiometricAuth.shouldOfferSetup {
                    MeshPrimaryButton(
                        title: isEnabling ? "Enabling…" : "Yes, use \(biometricName)",
                        isEnabled: canEnableNow && !isEnabling
                    ) {
                        Task { await enableBiometric() }
                    }

                    if !canEnableNow {
                        Text(MeshBiometricAuth.setupHint ?? "")
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Button(MeshBiometricAuth.shouldOfferSetup ? "No thanks" : "Continue") {
                    MeshPasscodeStore.setBiometricEnabled(false)
                    onFinished()
                }
                .font(MeshTheme.Typography.secondary())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }
        }
    }

    @MainActor
    private func enableBiometric() async {
        guard canEnableNow, !isEnabling else { return }
        isEnabling = true
        errorMessage = nil
        defer { isEnabling = false }

        let result = await MeshBiometricAuth.authenticate(
            reason: "Enable \(biometricName) to unlock Mesh"
        )
        switch result {
        case .success:
            MeshPasscodeStore.setBiometricEnabled(true)
            onFinished()
        case .cancelled:
            errorMessage = "Tap \"Yes\" when you're ready, or choose No thanks."
        case .biometryLockout:
            errorMessage = "\(biometricName) is locked. Try again later or choose No thanks."
        case .unavailable:
            errorMessage = MeshBiometricAuth.setupHint ?? "\(biometricName) is not available."
        case .failed:
            errorMessage = "Couldn't verify \(biometricName). Try again or choose No thanks."
        }
    }
}
