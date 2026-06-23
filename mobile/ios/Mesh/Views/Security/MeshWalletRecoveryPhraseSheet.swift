import SwiftUI

struct MeshWalletRecoveryPhraseContent: Identifiable, Equatable {
    let id: String
    let walletName: String
    let address: String
    let words: [String]
}

enum MeshWalletRecoveryPhraseLoader {
    static func load(walletID: String) -> MeshWalletRecoveryPhraseContent? {
        guard let wallet = MeshWalletRegistry.wallet(id: walletID),
              wallet.importKind == .mnemonic,
              let words = MeshMnemonicStore.loadWords(walletID: walletID),
              Valida.allowedMnemonicWordCounts.contains(words.count)
        else { return nil }

        return MeshWalletRecoveryPhraseContent(
            id: walletID,
            walletName: wallet.name,
            address: wallet.address,
            words: words
        )
    }
}

/// Shows recovery phrase after passcode verification.
struct MeshWalletRecoveryPhraseSheet: View {
    let content: MeshWalletRecoveryPhraseContent
    let onDone: () -> Void

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                MeshNavigationHeader(onClose: onDone)
                    .padding(.top, 4)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        MeshTitleBlock(
                            title: L10n.Onboarding.recoveryTitle,
                            subtitle: "\(content.walletName) · \(L10n.Onboarding.recoverySubtitle)",
                            centered: true
                        )

                        MeshSeedPhrasePanel(words: content.words)

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(MeshTheme.Typography.icon(size: 16, weight: .medium))
                                .foregroundStyle(Color.orange)
                            Text(L10n.Onboarding.recoveryNeverShare)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(MeshTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
