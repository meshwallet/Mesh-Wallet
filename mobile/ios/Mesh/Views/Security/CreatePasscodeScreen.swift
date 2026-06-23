import SwiftUI

struct CreatePasscodeScreen: View {
    var title: String = "Create passcode"
    var subtitle: String = "Be sure to remember it"
    let onBack: () -> Void
    let onContinue: (String) -> Void

    @State private var digits = ""
    @State private var shakeTrigger = false

    private var canContinue: Bool {
        digits.count == MeshPasscodeStore.digitCount
    }

    var body: some View {
        MeshOnboardingScreen {
            MeshPasscodeEntryLayout {
                MeshNavigationHeader(onBack: onBack)
                    .padding(.top, 4)
            } content: {
                passcodeBody
            }
        } footer: {
            MeshPrimaryButton(title: "Continue", isEnabled: canContinue) {
                onContinue(digits)
            }
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
        guard digits.count < MeshPasscodeStore.digitCount else { return }
        shakeTrigger = false
        digits.append(String(value))
    }

    private func removeLastDigit() {
        guard !digits.isEmpty else { return }
        shakeTrigger = false
        digits.removeLast()
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 8 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
