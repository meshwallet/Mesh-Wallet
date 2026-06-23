import SwiftUI

struct CreateWalletIntroScreen: View {
    let onBack: () -> Void
    let onContinue: (MeshWalletService.CreationResult) -> Void

    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var bullets: [String] {
        [
            "Phrase is generated locally on this device.",
            "Write down your backup and store it offline.",
            L10n.Onboarding.createIntroWarning
        ]
    }

    var body: some View {
        MeshOnboardingScreen {
            VStack(alignment: .leading, spacing: 0) {
                MeshNavigationHeader(onBack: onBack)
                    .padding(.top, 4)

                MeshTitleBlock(
                    title: L10n.Onboarding.createIntroTitle,
                    subtitle: L10n.Onboarding.createIntroSubtitle
                )
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.top, 8)

                MeshBulletList(items: bullets)
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 28)

                if let errorMessage {
                    Text(errorMessage)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                        .padding(.top, 16)
                }

                Spacer(minLength: 0)
            }
        } footer: {
            MeshPrimaryButton(
                title: isGenerating ? L10n.Common.generating : L10n.Onboarding.generateRecoveryPhrase,
                isEnabled: !isGenerating
            ) {
                generateWallet()
            }
        }
    }

    private func generateWallet() {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let created = try MeshWalletService.generateWallet()
            onContinue(created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
