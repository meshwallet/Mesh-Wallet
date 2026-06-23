import SwiftUI

struct CreateWalletBackupScreen: View {
    let words: [String]
    let expectedAddress: String
    let onBack: () -> Void
    let onProceed: (PendingWalletDraft) -> Void

    @State private var walletName = ""
    @State private var confirmedBackup = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var walletNamePlaceholder: String {
        MeshWalletRegistry.suggestedName(existingCount: MeshWalletRegistry.wallets.count)
    }

    var body: some View {
        MeshOnboardingScreen {
            VStack(spacing: 0) {
                MeshNavigationHeader(onBack: onBack)
                    .padding(.top, 4)

                MeshOnboardingScroll {
                    VStack(alignment: .leading, spacing: 24) {
                        MeshTitleBlock(
                            title: L10n.Onboarding.recoveryTitle,
                            subtitle: L10n.Onboarding.recoverySubtitle
                        )

                        MeshWalletNameField(name: $walletName, placeholder: walletNamePlaceholder)

                        MeshSeedPhrasePanel(words: words)

                        backupToggle

                        if let errorMessage {
                            Text(errorMessage)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        } footer: {
            MeshPrimaryButton(
                title: isSaving ? L10n.Common.saving : L10n.Common.continue_,
                isEnabled: confirmedBackup && !isSaving
            ) {
                Task { await finishCreate() }
            }
        }
    }

    private var backupToggle: some View {
        Button {
            confirmedBackup.toggle()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(
                            confirmedBackup ? MeshTheme.Colors.textPrimary : MeshTheme.Colors.border,
                            lineWidth: 1.5
                        )
                        .frame(width: 20, height: 20)
                    if confirmedBackup {
                        Image(systemName: "checkmark")
                            .font(MeshTheme.Typography.sans(size: 10, weight: .light))
                            .foregroundStyle(MeshTheme.Colors.textPrimary)
                    }
                }
                .padding(.top, 2)

                Text(L10n.Onboarding.recoveryConfirm)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(MeshRowButtonStyle())
    }

    @MainActor
    private func finishCreate() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let trimmedName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty, MeshWalletRegistry.isWalletNameTaken(trimmedName) {
                errorMessage = L10n.Error.walletNameTaken
                return
            }

            let derived = try MeshWalletService.importWallet(words: words)
            guard derived == expectedAddress else {
                errorMessage = L10n.Error.walletMismatch
                return
            }

            let draft = PendingWalletDraft(
                credential: .mnemonic(words: words),
                address: expectedAddress,
                walletName: walletName,
                flow: .created
            )
            onProceed(draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
