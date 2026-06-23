import SwiftUI

struct AppLockView: View {
    let onUnlocked: () -> Void

    @State private var digits = ""
    @State private var shakeTrigger = false
    @State private var hintMessage: String?
    @State private var isBiometricInProgress = false
    @State private var isVerifying = false
    @State private var showsBiometricUnlock = false
    @State private var biometricDisplayName = MeshBiometricAuth.displayName

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            MeshPasscodeEntryLayout {
                passcodeBody
            }
        }
        .onAppear {
            showsBiometricUnlock = MeshPasscodeStore.isBiometricEnabled && MeshBiometricAuth.isAvailable
            biometricDisplayName = MeshBiometricAuth.displayName
        }
    }

    private var passcodeBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            if showsBiometricUnlock {
                biometricUnlockSection
                    .padding(.bottom, 28)
            }

            MeshTitleBlock(
                title: "Enter passcode",
                subtitle: showsBiometricUnlock
                    ? "Or tap \(biometricDisplayName) above"
                    : nil,
                centered: true
            )
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)

            if let hintMessage {
                Text(hintMessage)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            }

            Spacer(minLength: 24)

            MeshPasscodeDots(
                filledCount: digits.count,
                total: MeshPasscodeStore.digitCount,
                hasError: shakeTrigger
            )
            .modifier(ShakeEffect(animatableData: shakeTrigger ? 1 : 0))

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

    private var biometricUnlockSection: some View {
        Button {
            Task { await unlockWithBiometric() }
        } label: {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(MeshTheme.Colors.fieldFill)
                        .frame(width: 88, height: 88)
                    if isBiometricInProgress {
                        ProgressView()
                            .tint(MeshTheme.Colors.accent)
                    } else {
                        Image(systemName: MeshBiometricAuth.systemImageName)
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(MeshTheme.Colors.accent)
                    }
                }

                Text(isBiometricInProgress ? "Checking…" : "Use \(biometricDisplayName)")
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBiometricInProgress || isVerifying)
    }

    private func appendDigit(_ value: Int) {
        guard !isVerifying, digits.count < MeshPasscodeStore.digitCount else { return }
        shakeTrigger = false
        hintMessage = nil
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
        let entered = digits
        isVerifying = true

        Task.detached(priority: .userInitiated) {
            let accepted = MeshPasscodeStore.verify(entered)
            await MainActor.run {
                if accepted {
                    digits = ""
                    onUnlocked()
                } else {
                    hintMessage = nil
                    withAnimation(.easeInOut(duration: 0.28)) {
                        shakeTrigger.toggle()
                    }
                    digits = ""
                }
                isVerifying = false
            }
        }
    }

    @MainActor
    private func unlockWithBiometric() async {
        guard !isBiometricInProgress, !isVerifying else { return }
        isBiometricInProgress = true
        hintMessage = nil
        defer { isBiometricInProgress = false }

        let result = await MeshBiometricAuth.authenticate(
            reason: "Unlock your Mesh wallet"
        )
        switch result {
        case .success:
            onUnlocked()
        case .cancelled:
            hintMessage = "Enter your Mesh passcode below"
        case .biometryLockout:
            hintMessage = "\(biometricDisplayName) is locked. Enter your Mesh passcode."
        case .unavailable:
            hintMessage = "\(biometricDisplayName) is unavailable. Enter your Mesh passcode."
        case .failed:
            hintMessage = "\(biometricDisplayName) didn't match. Enter your Mesh passcode."
        }
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 8 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
