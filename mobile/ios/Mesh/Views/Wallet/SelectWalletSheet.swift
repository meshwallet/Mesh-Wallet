import SwiftUI

struct SelectWalletSheet: View {
    private let sheetHorizontalPadding: CGFloat = 16
    private let walletRowSpacing: CGFloat = 10

    @Environment(\.dismiss) private var dismiss

    let accounts: [WalletAccount]
    let selectedAccountID: String
    let onSelect: (String) -> Void
    let onWalletRenamed: () -> Void
    let onWalletRemoved: (String) -> Void
    let onAddExisting: () -> Void
    let onCreateNew: () -> Void

    @State private var walletPendingRename: WalletAccount?
    @State private var walletPendingBackup: WalletAccount?
    @State private var walletPendingRemoval: WalletAccount?
    @State private var showRemoveWalletConfirm = false
    @State private var showRemoveWalletPasscode = false
    @State private var showBackupPasscode = false
    @State private var revealedRecoveryPhrase: MeshWalletRecoveryPhraseContent?
    @State private var phraseLoadError: String?

    private var canRemoveWallets: Bool {
        accounts.count > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.WalletSelect.title)
                .font(MeshTheme.Typography.sectionTitle())
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: walletRowSpacing) {
                    ForEach(accounts) { account in
                        walletRow(account)
                    }
                }
                .padding(.bottom, 12)
            }

            footerActions
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, sheetHorizontalPadding)
        .preferredColorScheme(.dark)
        .sheet(item: $walletPendingRename) { account in
            MeshRenameWalletSheet(
                walletID: account.id,
                currentName: account.name,
                onSaved: {
                    walletPendingRename = nil
                    onWalletRenamed()
                },
                onCancel: {
                    walletPendingRename = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MeshTheme.Colors.background)
            .interactiveDismissDisabled()
        }
        .confirmationDialog(
            L10n.Settings.removeConfirmTitle,
            isPresented: $showRemoveWalletConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.WalletSelect.menuRemove, role: .destructive) {
                requestRemoveWalletAuth()
            }
            Button(L10n.Common.cancel, role: .cancel) {
                walletPendingRemoval = nil
            }
        } message: {
            if let walletPendingRemoval {
                Text(removeConfirmMessage(for: walletPendingRemoval))
            }
        }
        .sheet(isPresented: $showRemoveWalletPasscode) {
            MeshPasscodeVerifySheet(
                title: L10n.WalletSelect.menuRemove,
                subtitle: L10n.Settings.recoveryRequiresPasscode,
                onVerified: {
                    showRemoveWalletPasscode = false
                    performRemoveWallet()
                },
                onCancel: {
                    showRemoveWalletPasscode = false
                    walletPendingRemoval = nil
                },
                showsBiometricRetry: true,
                biometricReason: L10n.Settings.removeAction
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MeshTheme.Colors.background)
            .interactiveDismissDisabled()
        }
        .alert(L10n.Settings.recoveryUnavailable, isPresented: Binding(
            get: { phraseLoadError != nil },
            set: { if !$0 { phraseLoadError = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) { phraseLoadError = nil }
        } message: {
            Text(phraseLoadError ?? "")
        }
        .sheet(isPresented: $showBackupPasscode) {
            MeshPasscodeVerifySheet(
                title: L10n.Settings.viewRecoveryPhrase,
                subtitle: L10n.Settings.viewRecoverySubtitle,
                onVerified: {
                    showBackupPasscode = false
                    presentBackupForPendingWallet()
                },
                onCancel: {
                    showBackupPasscode = false
                    walletPendingBackup = nil
                },
                showsBiometricRetry: true,
                biometricReason: L10n.Settings.viewRecoveryBiometricReason
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MeshTheme.Colors.background)
            .interactiveDismissDisabled()
        }
        .sheet(item: $revealedRecoveryPhrase) { content in
            MeshWalletRecoveryPhraseSheet(content: content) {
                revealedRecoveryPhrase = nil
                walletPendingBackup = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MeshTheme.Colors.background)
            .interactiveDismissDisabled()
        }
    }

    private func walletRow(_ account: WalletAccount) -> some View {
        let isSelected = account.id == selectedAccountID

        return HStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        }
                        .frame(width: 40, height: 40)
                    MeshWalletAssetIcon(size: 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(MeshTheme.Typography.sans(size: 16, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    Text(account.subtitle)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(account.id)
                dismiss()
            }

            Menu {
                Button {
                    walletPendingRename = account
                } label: {
                    MeshContextMenuLabel(
                        title: L10n.WalletSelect.menuRename,
                        systemImage: "pencil"
                    )
                }

                if supportsBackup(account) {
                    Button {
                        requestWalletBackup(for: account)
                    } label: {
                        MeshContextMenuLabel(
                            title: L10n.WalletSelect.menuBackup,
                            systemImage: "key.fill"
                        )
                    }
                }

                if canRemoveWallets {
                    Button {
                        walletPendingRemoval = account
                        showRemoveWalletConfirm = true
                    } label: {
                        MeshContextMenuLabel(
                            title: L10n.WalletSelect.menuRemove,
                            systemImage: "trash",
                            isDestructive: true
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(MeshTheme.Typography.icon(size: 16, weight: .medium))
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
                .fill(Color.black.opacity(0.34))
                .background {
                    RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.45))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
                        .stroke(
                            isSelected
                                ? MeshTheme.Colors.accent.opacity(0.55)
                                : Color.white.opacity(0.09),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            MeshSecondaryButton(
                title: L10n.WalletSelect.addExisting,
                icon: "plus",
                style: .outline
            ) {
                onAddExisting()
                dismiss()
            }

            MeshPrimaryButton(
                title: L10n.WalletSelect.createNew,
                assetIcon: MeshWalletIcons.wallet
            ) {
                onCreateNew()
                dismiss()
            }
        }
        .meshScreenFooterButtons()
    }

    private func supportsBackup(_ account: WalletAccount) -> Bool {
        MeshWalletRegistry.wallet(id: account.id)?.importKind == .mnemonic
    }

    private func requestWalletBackup(for account: WalletAccount) {
        walletPendingBackup = account
        Task {
            await MeshSensitiveAuth.authenticate(
                reason: L10n.Settings.viewRecoveryBiometricReason,
                onSuccess: { presentBackupForPendingWallet() },
                onNeedPasscode: { showBackupPasscode = true }
            )
        }
    }

    private func presentBackupForPendingWallet() {
        guard let account = walletPendingBackup else { return }
        if let content = MeshWalletRecoveryPhraseLoader.load(walletID: account.id) {
            revealedRecoveryPhrase = content
        } else {
            walletPendingBackup = nil
            phraseLoadError = L10n.Settings.recoveryNotStored
        }
    }

    private func removeConfirmMessage(for account: WalletAccount) -> String {
        switch MeshWalletRegistry.wallet(id: account.id)?.importKind {
        case .privateKey:
            return L10n.Settings.removeConfirmKey
        case .mnemonic, .none:
            return L10n.Settings.removeConfirmPhrase
        }
    }

    private func performRemoveWallet() {
        guard let account = walletPendingRemoval else { return }
        let removedID = account.id
        walletPendingRemoval = nil
        guard canRemoveWallets else { return }

        WalletSession.removeWallet(id: removedID)
        onWalletRemoved(removedID)

        if !WalletSession.hasActiveWallet {
            dismiss()
        }
    }

    private func requestRemoveWalletAuth() {
        guard MeshPasscodeStore.isEnabled else {
            performRemoveWallet()
            return
        }

        Task {
            await MeshSensitiveAuth.authenticate(
                reason: L10n.Settings.removeAction,
                onSuccess: { performRemoveWallet() },
                onNeedPasscode: { showRemoveWalletPasscode = true }
            )
        }
    }
}
