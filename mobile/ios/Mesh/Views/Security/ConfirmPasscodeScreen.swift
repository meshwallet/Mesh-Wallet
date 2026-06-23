import SwiftUI

struct ConfirmPasscodeScreen: View {
    var title: String = "Confirm passcode"
    var subtitle: String = "Enter the same passcode again"
    let draft: String
    var rejectMatchingPasscode: String?
    let onBack: () -> Void
    let onSuccess: () -> Void

    @State private var digits = ""
    @State private var shakeTrigger = false
    @State private var errorMessage: String?
    @State private var isConfirming = false

    var body: some View {
        MeshOnboardingScreen {
            MeshPasscodeEntryLayout {
                MeshNavigationHeader(onBack: onBack)
                    .padding(.top, 4)
            } content: {
                passcodeBody
            }
        } footer: {
            Color.clear
                .frame(height: MeshTheme.Metrics.buttonHeight + 12)
        }
    }

    private var passcodeBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            MeshTitleBlock(
                title: title,
                subtitle: subtitle,
                centered: true
            )
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)

            if let errorMessage {
                Text(errorMessage)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(Color.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            }

            Spacer(minLength: 32)

            MeshPasscodeDots(
                filledCount: digits.count,
                total: MeshPasscodeStore.digitCount,
                hasError: shakeTrigger
            )
            .modifier(ShakeEffect(animatableData: shakeTrigger ? 1 : 0))

            Spacer(minLength: 24)

            MeshPasscodeKeypad(
                onDigit: { appendDigit($0) },
                onDelete: { removeLastDigit() }
            )
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            .padding(.bottom, 16)
        }
    }

    private func appendDigit(_ value: Int) {
        guard digits.count < MeshPasscodeStore.digitCount, !isConfirming else { return }
        shakeTrigger = false
        errorMessage = nil
        digits.append(String(value))

        if digits.count == MeshPasscodeStore.digitCount {
            confirmPasscode()
        }
    }

    private func removeLastDigit() {
        guard !digits.isEmpty else { return }
        shakeTrigger = false
        errorMessage = nil
        digits.removeLast()
    }

    private func confirmPasscode() {
        guard !isConfirming else { return }
        isConfirming = true
        defer { isConfirming = false }

        guard digits == draft else {
            errorMessage = "Passcodes do not match. Try again."
            shakeTrigger.toggle()
            digits = ""
            return
        }

        if let rejectMatchingPasscode, digits == rejectMatchingPasscode {
            errorMessage = "New passcode must be different from your current passcode."
            shakeTrigger.toggle()
            digits = ""
            return
        }

        guard MeshPasscodeStore.setPasscode(digits) else {
            errorMessage = "Could not save passcode. Try again."
            digits = ""
            return
        }

        Task { @MainActor in
            onSuccess()
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
