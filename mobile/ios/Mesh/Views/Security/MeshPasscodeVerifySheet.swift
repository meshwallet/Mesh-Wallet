import SwiftUI

/// Passcode gate for sensitive actions; optional Face ID / Touch ID retry.
struct MeshPasscodeVerifySheet: View {
    let title: String
    let subtitle: String
    let onVerified: () -> Void
    let onCancel: () -> Void
    var showsBiometricRetry: Bool = false
    var biometricReason: String = ""

    @State private var digits = ""
    @State private var shakeTrigger = false
    @State private var errorMessage: String?
    @State private var isBiometricInProgress = false
    @State private var isVerifying = false

    private var canRetryBiometric: Bool {
        showsBiometricRetry && MeshSensitiveAuth.canUseBiometric
    }

    private var resolvedBiometricReason: String {
        let trimmed = biometricReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return L10n.Settings.viewRecoveryBiometricReason
    }

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            MeshPasscodeEntryLayout {
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(MeshTheme.Typography.secondary())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                }
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.top, 8)
            } content: {
                passcodeBody
            }
        }
        .preferredColorScheme(.dark)
    }

    private var passcodeBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            MeshTitleBlock(title: title, subtitle: displaySubtitle, centered: true)
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)

            if let errorMessage {
                Text(errorMessage)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(Color.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            }

            if canRetryBiometric {
                biometricRetryButton
                    .padding(.top, 20)
            }

            Spacer(minLength: canRetryBiometric ? 16 : 24)

            MeshPasscodeDots(
                filledCount: digits.count,
                total: MeshPasscodeStore.digitCount,
                hasError: shakeTrigger
            )
            .modifier(MeshPasscodeShakeEffect(animatableData: shakeTrigger ? 1 : 0))

            Spacer(minLength: 20)

            MeshPasscodeKeypad(
                onDigit: { appendDigit($0) },
                onDelete: { removeLastDigit() }
            )
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            .disabled(isVerifying)

            Spacer(minLength: 24)
        }
    }

    private var displaySubtitle: String {
        if canRetryBiometric {
            return L10n.Settings.viewRecoverySubtitleBiometric(MeshBiometricAuth.displayName)
        }
        return subtitle
    }

    private var biometricRetryButton: some View {
        Button {
            Task { await retryBiometric() }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MeshTheme.Colors.fieldFill)
                        .frame(width: 72, height: 72)
                    if isBiometricInProgress {
                        ProgressView()
                            .tint(MeshTheme.Colors.accent)
                    } else {
                        Image(systemName: MeshBiometricAuth.systemImageName)
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(MeshTheme.Colors.accent)
                    }
                }
                Text(
                    isBiometricInProgress
                        ? "Checking…"
                        : L10n.Security.unlockWith(MeshBiometricAuth.displayName)
                )
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBiometricInProgress)
    }

    private func appendDigit(_ value: Int) {
        guard !isVerifying, digits.count < MeshPasscodeStore.digitCount else { return }
        shakeTrigger = false
        errorMessage = nil
        digits.append(String(value))
        if digits.count == MeshPasscodeStore.digitCount {
            verifyPasscode()
        }
    }

    private func removeLastDigit() {
        guard !isVerifying, !digits.isEmpty else { return }
        shakeTrigger = false
        digits.removeLast()
    }

    private func verifyPasscode() {
        guard !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }

        guard MeshPasscodeStore.isEnabled else {
            errorMessage = "Passcode is not set up."
            digits = ""
            return
        }

        if MeshPasscodeStore.verify(digits) {
            digits = ""
            Task { @MainActor in
                onVerified()
            }
        } else {
            errorMessage = L10n.Security.passcodeIncorrect
            withAnimation(.easeInOut(duration: 0.28)) {
                shakeTrigger.toggle()
            }
            digits = ""
        }
    }

    @MainActor
    private func retryBiometric() async {
        guard canRetryBiometric, !isBiometricInProgress else { return }
        isBiometricInProgress = true
        errorMessage = nil
        defer { isBiometricInProgress = false }

        let result = await MeshBiometricAuth.authenticate(reason: resolvedBiometricReason)
        switch result {
        case .success:
            onVerified()
        case .cancelled:
            break
        case .biometryLockout:
            errorMessage = "\(MeshBiometricAuth.displayName) is locked. Enter your passcode."
        case .unavailable:
            errorMessage = "\(MeshBiometricAuth.displayName) is unavailable. Enter your passcode."
        case .failed:
            errorMessage = "\(MeshBiometricAuth.displayName) didn't match. Enter your passcode."
        }
    }
}

struct MeshPasscodeShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 8 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
