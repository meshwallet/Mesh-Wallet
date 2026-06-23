import SwiftUI

struct WalletSecurityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meshModalClose) private var meshModalClose
    @Environment(\.meshInteractiveDismiss) private var meshInteractiveDismiss
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var languageStore: MeshLanguageStore

    @State private var biometricEnabled = MeshPasscodeStore.isBiometricEnabled
    @State private var isUpdatingBiometric = false
    @State private var biometricMessage: String?
    @State private var showRemoveWalletPasscode = false
    @State private var showRemoveWalletConfirm = false
    @State private var showRecoveryPhrasePasscode = false
    @State private var showChangePasscode = false
    @State private var passcodeChanged = false
    @State private var revealedRecoveryPhrase: MeshWalletRecoveryPhraseContent?
    @State private var phraseLoadError: String?
    @State private var ignoreToggleChanges = false
    @State private var inAppBrowserURL: URL?

    private var biometricName: String {
        MeshBiometricAuth.displayName
    }

    private var removeWalletMessage: String {
        if MeshWalletCredentials.supportsHDWalletFeatures() {
            return L10n.Settings.removeConfirmPhrase
        }
        return L10n.Settings.removeConfirmKey
    }

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                MeshFlowScreenHeader(title: L10n.Settings.title, onClose: closeModal)
                    .padding(.top, 4)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        biometricsCard
                        passcodeInfoCard
                        languageCard
                        if MeshWalletCredentials.supportsHDWalletFeatures() {
                            viewRecoveryPhraseCard
                        }
                        if WalletSession.canRemoveActiveWallet {
                            removeWalletCard
                        }
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }

                supportCard
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)

                appVersionFooter
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            syncBiometricToggleFromStore()
        }
        .confirmationDialog(
            L10n.Settings.removeConfirmTitle,
            isPresented: $showRemoveWalletConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.Settings.removeAction, role: .destructive) {
                requestRemoveWalletAuth()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(removeWalletMessage)
        }
        .alert(L10n.Settings.passcodeUpdatedTitle, isPresented: $passcodeChanged) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(L10n.Settings.passcodeUpdatedMessage)
        }
        .sheet(isPresented: $showChangePasscode) {
            ChangePasscodeFlowView {
                showChangePasscode = false
                passcodeChanged = true
            }
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
        .sheet(isPresented: $showRemoveWalletPasscode) {
            MeshPasscodeVerifySheet(
                title: L10n.Settings.removeAction,
                subtitle: L10n.Settings.recoveryRequiresPasscode,
                onVerified: {
                    showRemoveWalletPasscode = false
                    performRemoveWallet()
                },
                onCancel: {
                    showRemoveWalletPasscode = false
                },
                showsBiometricRetry: true,
                biometricReason: L10n.Settings.removeAction
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MeshTheme.Colors.background)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showRecoveryPhrasePasscode) {
            MeshPasscodeVerifySheet(
                title: L10n.Settings.viewRecoveryPhrase,
                subtitle: L10n.Settings.viewRecoverySubtitle,
                onVerified: {
                    showRecoveryPhrasePasscode = false
                    revealActiveWalletRecoveryPhrase()
                },
                onCancel: {
                    showRecoveryPhrasePasscode = false
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
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MeshTheme.Colors.background)
            .interactiveDismissDisabled()
        }
        .meshInAppBrowserSheet(url: $inAppBrowserURL)
    }

    private var biometricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MeshTheme.Colors.fieldFill)
                        .frame(width: 44, height: 44)
                    Image(systemName: MeshBiometricAuth.systemImageName)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(MeshTheme.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(biometricName)
                        .font(MeshTheme.Typography.sans(size: 16, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    Text(biometricSubtitle)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $biometricEnabled)
                    .labelsHidden()
                    .tint(MeshTheme.Colors.accent)
                    .disabled(!canToggleBiometric)
            }

            if isUpdatingBiometric {
                Text(L10n.Settings.biometricConfirm(biometricName))
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
            } else if let biometricMessage {
                Text(biometricMessage)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MeshTheme.Colors.listCardFill,
            in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
        )
        .onChange(of: biometricEnabled) { enabled in
            guard !ignoreToggleChanges else { return }
            Task { await updateBiometric(enabled) }
        }
    }

    private var biometricSubtitle: String {
        if !MeshPasscodeStore.isEnabled {
            return L10n.Settings.biometricSetupFirst
        }
        if !MeshBiometricAuth.shouldOfferSetup {
            return L10n.Settings.biometricUnavailableDevice
        }
        if !MeshBiometricAuth.isAvailable {
            return MeshBiometricAuth.setupHint ?? L10n.Settings.biometricSetupSettings(biometricName)
        }
        return L10n.Settings.biometricUnlockHint(biometricName)
    }

    private var canToggleBiometric: Bool {
        MeshPasscodeStore.isEnabled
            && MeshBiometricAuth.shouldOfferSetup
            && !isUpdatingBiometric
    }

    private var passcodeInfoCard: some View {
        Group {
            if MeshPasscodeStore.isEnabled {
                Button {
                    showChangePasscode = true
                } label: {
                    passcodeRowContent(
                        subtitle: L10n.Settings.passcodeChange,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                passcodeRowContent(
                    subtitle: L10n.Settings.passcodeSetupHint,
                    showsChevron: false
                )
            }
        }
    }

    private var languageCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MeshTheme.Colors.fieldFill)
                    .frame(width: 44, height: 44)
                Image(systemName: "globe")
                    .font(MeshTheme.Typography.icon(size: 18, weight: .medium))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Language.title)
                    .font(MeshTheme.Typography.sans(size: 16, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                Text(L10n.Language.subtitle)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Menu {
                Picker(L10n.Language.title, selection: Binding(
                    get: { languageStore.selected },
                    set: { languageStore.setLanguage($0) }
                )) {
                    ForEach(MeshAppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(languageStore.selected.displayName)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(MeshTheme.Typography.icon(size: 10, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textTertiary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MeshTheme.Colors.listCardFill,
            in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
        )
    }

    private func passcodeRowContent(subtitle: String, showsChevron: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MeshTheme.Colors.fieldFill)
                    .frame(width: 44, height: 44)
                Image(systemName: "lock.fill")
                    .font(MeshTheme.Typography.icon(size: 18, weight: .medium))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Settings.passcode)
                    .font(MeshTheme.Typography.sans(size: 16, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(MeshTheme.Typography.icon(size: 14, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(MeshTheme.Typography.icon(size: 20, weight: .medium))
                    .foregroundStyle(MeshTheme.Colors.success)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MeshTheme.Colors.listCardFill,
            in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
        )
        .accessibilityHint(subtitle)
    }

    private var viewRecoveryPhraseCard: some View {
        Button {
            requestViewRecoveryPhrase()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MeshTheme.Colors.fieldFill)
                        .frame(width: 44, height: 44)
                    Image(systemName: "doc.text")
                        .font(MeshTheme.Typography.icon(size: 18, weight: .medium))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Settings.recoveryPhrase)
                        .font(MeshTheme.Typography.sans(size: 16, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    Text(recoveryAccessHint)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(MeshTheme.Typography.icon(size: 14, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MeshTheme.Colors.listCardFill,
                in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
            )
            .accessibilityHint(recoveryAccessHint)
        }
        .buttonStyle(.plain)
    }

    private var recoveryAccessHint: String {
        if MeshSensitiveAuth.canUseBiometric {
            return L10n.Settings.viewRecoverySubtitleBiometric(MeshBiometricAuth.displayName)
        }
        return L10n.Settings.recoveryRequiresPasscode
    }

    private func requestViewRecoveryPhrase() {
        Task {
            await MeshSensitiveAuth.authenticate(
                reason: L10n.Settings.viewRecoveryBiometricReason,
                onSuccess: { revealActiveWalletRecoveryPhrase() },
                onNeedPasscode: { showRecoveryPhrasePasscode = true }
            )
        }
    }

    private func revealActiveWalletRecoveryPhrase() {
        guard let walletID = MeshWalletRegistry.activeWalletID else {
            phraseLoadError = L10n.Settings.recoveryNoWallet
            return
        }
        if let content = MeshWalletRecoveryPhraseLoader.load(walletID: walletID) {
            revealedRecoveryPhrase = content
        } else {
            phraseLoadError = L10n.Settings.recoveryNotStored
        }
    }

    private var removeWalletCard: some View {
        Button {
            showRemoveWalletConfirm = true
        } label: {
            Text(L10n.Settings.removeWallet)
                .font(MeshTheme.Typography.sans(size: 16, weight: .medium))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(
                    MeshTheme.Colors.listCardFill,
                    in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var supportCard: some View {
        MeshSecondaryButton(title: L10n.Settings.contactSupport) {
            inAppBrowserURL = MeshAppLinks.contactPage
        }
            .meshScreenFooterButtons()
            .padding(.top, 4)
    }

    private var appVersionFooter: some View {
        Group {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text(version)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textTertiary.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
            }
        }
    }

    @MainActor
    private func syncBiometricToggleFromStore() {
        ignoreToggleChanges = true
        biometricEnabled = MeshPasscodeStore.isBiometricEnabled
        ignoreToggleChanges = false
    }

    @MainActor
    private func updateBiometric(_ enabled: Bool) async {
        guard !isUpdatingBiometric else { return }
        isUpdatingBiometric = true
        biometricMessage = nil
        defer { isUpdatingBiometric = false }

        if enabled {
            guard MeshBiometricAuth.shouldOfferSetup else {
                revertBiometricToggle(to: false)
                biometricMessage = L10n.Settings.biometricNotAvailable
                return
            }
            guard MeshBiometricAuth.isAvailable else {
                revertBiometricToggle(to: false)
                biometricMessage = MeshBiometricAuth.setupHint ?? L10n.Settings.biometricNotSetup(biometricName)
                return
            }

            let result = await MeshBiometricAuth.authenticate(
                reason: L10n.Settings.biometricEnableReason(biometricName)
            )
            switch result {
            case .success:
                MeshPasscodeStore.setBiometricEnabled(true)
            case .cancelled, .biometryLockout, .failed:
                revertBiometricToggle(to: false)
            case .unavailable:
                revertBiometricToggle(to: false)
                biometricMessage = MeshBiometricAuth.setupHint ?? L10n.Settings.biometricNotAvailable
            }
        } else {
            MeshPasscodeStore.setBiometricEnabled(false)
        }
    }

    @MainActor
    private func revertBiometricToggle(to value: Bool) {
        ignoreToggleChanges = true
        biometricEnabled = value
        ignoreToggleChanges = false
    }

    private func performRemoveWallet() {
        WalletSession.reset()
        closeModal()
        coordinator.refreshRoute()
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

    private func closeModal() {
        MeshModalClose.perform(
            modalClose: meshModalClose,
            interactiveDismiss: meshInteractiveDismiss,
            dismiss: dismiss
        )
    }
}
