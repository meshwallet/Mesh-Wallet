import SwiftUI

struct OnboardingFlowView: View {
    var startPoint: OnboardingStartPoint = .welcome
    var createFlowModel: WalletCreateFlowModel?
    let onFinished: () -> Void
    var onCancelFromRoot: (() -> Void)?

    @State private var path = NavigationPath()
    @State private var showSecuritySheet = false
    @State private var screenWidth: CGFloat = 390
    @State private var shouldShowWalletReady = false
    @State private var isCommittingWallet = false
    @State private var pendingCreateDraft: PendingWalletDraft?
    @State private var committedWalletAddress: String?
    @State private var walletCreationError: String?

    private var horizontalInset: CGFloat {
        MeshLayout.horizontalInset(width: screenWidth)
    }

    private var managesCreationGate: Bool {
        createFlowModel == nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootView
                .navigationDestination(for: OnboardingRoute.self) { route in
                    destination(for: route)
                }
        }
        .meshPublishScreenWidth($screenWidth)
        .environment(\.meshHorizontalInset, horizontalInset)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSecuritySheet) {
            SeedPhraseSecuritySheet {
                path.append(OnboardingRoute.restorePhrase)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MeshTheme.Colors.background)
        }
        .preferredColorScheme(.dark)
        .task(id: startPoint) {
            switch startPoint {
            case .create:
                await resumeOrStartWalletCreation(allowNewGeneration: true)
            case .welcome:
                await resumeOrStartWalletCreation(allowNewGeneration: false)
            case .addExisting:
                break
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch startPoint {
        case .welcome:
            WelcomeScreen(
                onCreate: { Task { await resumeOrStartWalletCreation(allowNewGeneration: true) } },
                onRestore: { path.append(OnboardingRoute.addExistingWallet) }
            )
        case .addExisting:
            AddExistingWalletScreen(
                onBack: { cancelFlow() },
                onSecretPhrase: { showSecuritySheet = true },
                onPrivateKey: { path.append(OnboardingRoute.restorePrivateKey) }
            )
            .meshOnboardingChrome(onBack: { cancelFlow() })
        case .create:
            CreateWalletLaunchScreen(
                onBack: { cancelFlow() },
                errorMessage: walletCreationError
            )
            .meshOnboardingChrome(onBack: { cancelFlow() })
        }
    }

    @ViewBuilder
    private func destination(for route: OnboardingRoute) -> some View {
        Group {
            switch route {
            case .welcome:
                EmptyView()
            case .addExistingWallet:
                AddExistingWalletScreen(
                    onBack: { path.removeLast() },
                    onSecretPhrase: { showSecuritySheet = true },
                    onPrivateKey: { path.append(OnboardingRoute.restorePrivateKey) }
                )
            case .restorePhrase:
                RestorePhraseScreen(
                    onBack: { path.removeLast() },
                    onProceed: proceedAfterWalletPrepared
                )
            case .createLaunch:
                CreateWalletLaunchScreen(
                    onBack: { path.removeLast() },
                    errorMessage: walletCreationError
                )
            case .setupPasscode(let pending):
                CreatePasscodeScreen(
                    onBack: { path.removeLast() },
                    onContinue: { draft in
                        path.append(OnboardingRoute.confirmPasscode(draft: draft, pending: pending))
                    }
                )
            case .confirmPasscode(let draft, let pending):
                ConfirmPasscodeScreen(
                    draft: draft,
                    onBack: { path.removeLast() },
                    onSuccess: {
                        Task { await finishPasscodeAndCommitWallet(pending: pending) }
                    }
                )
            case .faceIDSetup:
                SecureWalletBiometricScreen(onFinished: finishBiometricStep)
            case .walletReady:
                WalletReadyScreen(onStart: completeOnboardingFlow)
            case .restorePrivateKey:
                RestorePrivateKeyScreen(
                    onBack: { path.removeLast() },
                    onProceed: proceedAfterWalletPrepared
                )
            }
        }
        .meshOnboardingChrome(onBack: chromeBackAction(for: route))
    }

    private func chromeBackAction(for route: OnboardingRoute) -> (() -> Void)? {
        switch route {
        case .walletReady, .createLaunch:
            return nil
        default:
            return popOnboardingPath
        }
    }

    private func popOnboardingPath() {
        guard !path.isEmpty else {
            cancelFlow()
            return
        }
        path.removeLast()
    }

    @MainActor
    private func resumeOrStartWalletCreation(allowNewGeneration: Bool) async {
        if let draft = MeshWalletCreationGate.storedDraft {
            adoptGeneratedDraft(draft)
            return
        }
        guard !MeshWalletCreationGate.hasCommitted else { return }
        guard allowNewGeneration else { return }

        if let createFlowModel, createFlowModel.didStart {
            return
        }

        guard MeshWalletCreationGate.tryBeginGeneration() else { return }
        if let createFlowModel {
            createFlowModel.markStarted()
        }
        walletCreationError = nil

        do {
            let created = try MeshWalletService.generateWallet()
            let draft = PendingWalletDraft(
                credential: .mnemonic(words: created.words),
                address: created.address,
                walletName: "",
                flow: .created
            )
            proceedAfterWalletGenerated(draft)
        } catch {
            MeshWalletCreationGate.abortGeneration()
            createFlowModel?.reset()
            walletCreationError = error.localizedDescription
            if startPoint == .welcome, path.isEmpty {
                path.append(OnboardingRoute.createLaunch)
            }
        }
    }

    private func proceedAfterWalletGenerated(_ draft: PendingWalletDraft) {
        guard MeshWalletCreationGate.captureDraft(draft) else { return }
        adoptGeneratedDraft(draft)
    }

    private func adoptGeneratedDraft(_ draft: PendingWalletDraft) {
        pendingCreateDraft = draft

        if let existing = MeshWalletRegistry.wallet(address: draft.address) {
            MeshWalletRegistry.setActiveWallet(id: existing.id)
            committedWalletAddress = existing.address
            if draft.flow == .created, path.isEmpty {
                path.append(OnboardingRoute.walletReady)
            }
            return
        }

        guard path.isEmpty else { return }
        if MeshPasscodeStore.isEnabled {
            Task { await commitWalletAndFinishIfNeeded(draft) }
        } else {
            path.append(OnboardingRoute.setupPasscode(draft))
        }
    }

    private func proceedAfterWalletPrepared(_ draft: PendingWalletDraft) {
        _ = MeshWalletCreationGate.captureDraft(draft)
        if MeshPasscodeStore.isEnabled {
            Task { await commitWalletAndFinishIfNeeded(draft) }
        } else {
            path.append(OnboardingRoute.setupPasscode(draft))
        }
    }

    @MainActor
    private func finishPasscodeAndCommitWallet(pending: PendingWalletDraft) async {
        guard !isCommittingWallet else { return }
        isCommittingWallet = true
        defer { isCommittingWallet = false }

        guard await commitPendingWallet(pending) else { return }
        shouldShowWalletReady = pending.flow == .created
        proceedAfterPasscodeConfirmed()
    }

    @MainActor
    private func commitWalletAndFinishIfNeeded(_ draft: PendingWalletDraft) async {
        guard !isCommittingWallet else { return }
        isCommittingWallet = true
        defer { isCommittingWallet = false }

        guard await commitPendingWallet(draft) else { return }
        if draft.flow == .created {
            path.append(OnboardingRoute.walletReady)
        } else {
            WalletSession.markOnboardingComplete()
            resetCreationGateIfNeeded()
            onFinished()
        }
    }

    @MainActor
    private func commitPendingWallet(_ draft: PendingWalletDraft) async -> Bool {
        if let existing = MeshWalletRegistry.wallet(address: draft.address) {
            MeshWalletRegistry.setActiveWallet(id: existing.id)
            committedWalletAddress = existing.address
            return true
        }

        guard MeshWalletCreationGate.tryCommitAddress(draft.address) else { return false }

        if let committedWalletAddress,
           committedWalletAddress != draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        {
            return false
        }

        guard MeshWalletCreationGate.tryBeginCommit(for: draft.address) else {
            if let existing = MeshWalletRegistry.wallet(address: draft.address) {
                MeshWalletRegistry.setActiveWallet(id: existing.id)
                committedWalletAddress = existing.address
                return true
            }
            return false
        }
        defer { MeshWalletCreationGate.finishCommit() }

        do {
            let name = draft.walletName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? nil : name

            let address: String
            switch draft.credential {
            case .mnemonic(let words):
                address = try MeshWalletService.activateWallet(words: words, name: displayName)
            case .privateKey(let hex):
                address = try MeshWalletService.activateWallet(
                    privateKeyHex: hex,
                    expectedAddress: draft.address,
                    name: displayName
                )
            }

            guard address == draft.address else { return false }

            committedWalletAddress = address
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private func proceedAfterPasscodeConfirmed() {
        path.append(OnboardingRoute.faceIDSetup)
    }

    private func finishBiometricStep() {
        if shouldShowWalletReady {
            shouldShowWalletReady = false
            path.append(OnboardingRoute.walletReady)
        } else {
            completeOnboardingFlow()
        }
    }

    private func completeOnboardingFlow() {
        WalletSession.markOnboardingComplete()
        resetCreationGateIfNeeded()
        onFinished()
    }

    private func cancelFlow() {
        resetCreationGateIfNeeded()
        onCancelFromRoot?()
    }

    private func resetCreationGateIfNeeded() {
        guard managesCreationGate else { return }
        MeshWalletCreationGate.reset()
    }
}
