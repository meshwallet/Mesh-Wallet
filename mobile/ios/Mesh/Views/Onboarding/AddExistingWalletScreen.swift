import SwiftUI

struct AddExistingWalletScreen: View {
    let onBack: () -> Void
    let onSecretPhrase: () -> Void
    let onPrivateKey: () -> Void

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                MeshNavigationHeader(onBack: onBack)
                    .padding(.top, 4)

                Text(L10n.Onboarding.addExistingTitle)
                    .font(MeshTheme.Typography.screenTitle())
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)

                Text(L10n.Onboarding.addExistingSubtitle)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)

                Spacer(minLength: 16)

                heroImage

                Spacer(minLength: 16)

                VStack(spacing: 12) {
                    MeshSecondaryButton(
                        title: L10n.Onboarding.restorePhraseTitle,
                        icon: "text.alignleft",
                        style: .field,
                        action: onSecretPhrase
                    )
                    MeshSecondaryButton(
                        title: L10n.Onboarding.restoreKeyTitle,
                        icon: "key",
                        style: .field,
                        action: onPrivateKey
                    )
                }
                .meshScreenFooterButtons()
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.bottom, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var heroImage: some View {
        Image("WelcomeHero")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

}
