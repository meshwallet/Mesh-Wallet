import SwiftUI

struct WelcomeScreen: View {
    let onCreate: () -> Void
    let onRestore: () -> Void

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroImage
                            .padding(.top, 12)

                        VStack(spacing: 12) {
                            Image("IconPng")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 48)
                                .accessibilityLabel(L10n.Welcome.brand)

                            Text(L10n.Welcome.tagline)
                                .font(MeshTheme.Typography.secondary())
                                .foregroundStyle(MeshTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)

                VStack(spacing: 12) {
                    MeshSecondaryButton(
                        title: L10n.Welcome.restore,
                        style: .outline,
                        action: onRestore
                    )
                    MeshPrimaryButton(title: L10n.Welcome.create, action: onCreate)
                }
                .meshScreenFooterButtons()
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)

                legalFooter
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
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

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text(L10n.Welcome.legalPrefix)
                .font(MeshTheme.Typography.sans(size: 12, weight: .regular))
                .foregroundStyle(MeshTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                legalLinkButton(
                    title: L10n.Welcome.terms,
                    url: MeshAppLinks.termsPage
                )
                Text(L10n.Common.and)
                    .font(MeshTheme.Typography.sans(size: 12, weight: .regular))
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
                legalLinkButton(
                    title: L10n.Welcome.privacy,
                    url: MeshAppLinks.privacyPage
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func legalLinkButton(title: String, url: URL?) -> some View {
        Button {
            MeshAppLinks.open(url)
        } label: {
            Text(title)
                .font(MeshTheme.Typography.sans(size: 12, weight: .medium))
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .underline()
        }
        .buttonStyle(.plain)
    }
}
