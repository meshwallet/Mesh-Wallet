import SwiftUI

/// Settings flow: verify current passcode → enter new → confirm.
struct ChangePasscodeFlowView: View {
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void

    @State private var step: Step = .verifyCurrent
    @State private var verifiedCurrentPasscode: String?

    private enum Step: Equatable {
        case verifyCurrent
        case enterNew
        case confirmNew(String)
    }

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            switch step {
            case .verifyCurrent:
                verifyCurrentStep
            case .enterNew:
                CreatePasscodeScreen(
                    title: "New passcode",
                    subtitle: "Choose a new 6-digit passcode",
                    onBack: { step = .verifyCurrent },
                    onContinue: { step = .confirmNew($0) }
                )
            case .confirmNew(let draft):
                ConfirmPasscodeScreen(
                    title: "Confirm passcode",
                    subtitle: "Enter the same passcode again",
                    draft: draft,
                    rejectMatchingPasscode: verifiedCurrentPasscode,
                    onBack: { step = .enterNew },
                    onSuccess: completeChange
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    private var verifyCurrentStep: some View {
        MeshPasscodeEntryLayout {
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
            }
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            .padding(.top, 8)
        } content: {
            VerifyCurrentPasscodeContent(
                title: "Current passcode",
                subtitle: "Enter your current passcode to continue",
                onVerified: { current in
                    verifiedCurrentPasscode = current
                    step = .enterNew
                }
            )
        }
    }

    private func completeChange() {
        verifiedCurrentPasscode = nil
        onSuccess()
        dismiss()
    }
}

/// Shared verify UI for change-passcode (auto-submit on 6 digits).
private struct VerifyCurrentPasscodeContent: View {
    let title: String
    let subtitle: String
    let onVerified: (String) -> Void

    @State private var digits = ""
    @State private var shakeTrigger = false
    @State private var errorMessage: String?
    @State private var isVerifying = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            MeshTitleBlock(title: title, subtitle: subtitle, centered: true)
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)

            if let errorMessage {
                Text(errorMessage)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(Color.orange)
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

    private func appendDigit(_ value: Int) {
        guard !isVerifying, digits.count < MeshPasscodeStore.digitCount else { return }
        shakeTrigger = false
        errorMessage = nil
        digits.append(String(value))
        if digits.count == MeshPasscodeStore.digitCount {
            verify()
        }
    }

    private func removeLastDigit() {
        guard !isVerifying, !digits.isEmpty else { return }
        shakeTrigger = false
        errorMessage = nil
        digits.removeLast()
    }

    private func verify() {
        guard !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }

        guard MeshPasscodeStore.isEnabled else {
            errorMessage = "Passcode is not set up."
            digits = ""
            return
        }

        if MeshPasscodeStore.verify(digits) {
            let verified = digits
            digits = ""
            onVerified(verified)
        } else {
            errorMessage = "Incorrect passcode. Try again."
            withAnimation(.easeInOut(duration: 0.28)) {
                shakeTrigger.toggle()
            }
            digits = ""
        }
    }
}
