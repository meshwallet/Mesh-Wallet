import SwiftUI

struct SendFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meshModalClose) private var meshModalClose
    @Environment(\.meshInteractiveDismiss) private var meshInteractiveDismiss
    @ObservedObject var model: SendFlowViewModel
    @ObservedObject var sendFlowBinding: SendFlowBinding
    let initialSpendableUSDT: Decimal?
    let initialBalanceIsKnown: Bool

    @State private var path = NavigationPath()
    @State private var showQRScanner = false
    @State private var biometricAlertMessage: String?

    init(
        model: SendFlowViewModel,
        sendFlowBinding: SendFlowBinding,
        initialSpendableUSDT: Decimal? = nil,
        initialBalanceIsKnown: Bool = false
    ) {
        self.model = model
        self.sendFlowBinding = sendFlowBinding
        self.initialSpendableUSDT = initialSpendableUSDT
        self.initialBalanceIsKnown = initialBalanceIsKnown
    }

    var body: some View {
        NavigationStack(path: $path) {
            SendAddressStepView(
                model: model,
                onClose: closeModal,
                onPaste: pasteAddress,
                onScanQR: { showQRScanner = true },
                onNext: advanceToReview
            )
            .navigationDestination(for: SendRoute.self) { route in
                switch route {
                case .review:
                    SendReviewStepView(
                        model: model,
                        onBack: { path.removeLast() },
                        onBeginSend: {
                            beginSendFromReview()
                        }
                    )
                case .sending:
                    SendSubmittedView(
                        model: model,
                        onClose: finishSendAndClose
                    )
                case .success(let txID):
                    SendSuccessView(
                        model: model,
                        txID: txID,
                        onDone: finishSendAndClose
                    )
                case .failed(let message):
                    SendFailedView(
                        model: model,
                        message: message,
                        onCancel: closeModal
                    )
                }
            }
        }
        .task {
            await model.loadWalletState()
            model.revalidateDraftAfterBalanceRefresh()
            TronBlockService.prefetchLatestBlock()
        }
        .onAppear { restoreSendFlowIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .meshWalletBalancesShouldRefresh)) { _ in
            Task { await model.loadWalletState() }
        }
        .sheet(isPresented: $showQRScanner) {
            TronQRScannerSheet { code in
                model.recipientAddress = code
                model.addressError = nil
                showQRScanner = false
            }
        }
        .alert("Face ID required", isPresented: Binding(
            get: { biometricAlertMessage != nil },
            set: { if !$0 { biometricAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { biometricAlertMessage = nil }
        } message: {
            Text(biometricAlertMessage ?? "")
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func advanceToReview() {
        guard !model.isAddressStepBusy else { return }
        dismissKeyboardForSend()
        guard model.validateForReview() else { return }
        TronBlockService.prefetchLatestBlock()
        model.isAddressStepBusy = true
        path.append(SendRoute.review)
        model.isAddressStepBusy = false
    }

    @MainActor
    private func restoreSendFlowIfNeeded() {
        if model.hasPersistedFormContent {
            model.amountError = nil
        }
        TronBlockService.prefetchLatestBlock()
    }

    private func finishSendAndClose() {
        let walletID = MeshWalletRegistry.activeWalletID
        model.clearSendDraft()
        if let walletID {
            sendFlowBinding.refreshAfterDraftCleared(walletID: walletID)
        }
        closeModal()
    }

    private func dismissKeyboardForSend() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    private func closeModal() {
        MeshBackgroundSendService.shared.abandonEphemeralPendingSendIfNeeded()
        MeshModalClose.perform(
            modalClose: meshModalClose,
            interactiveDismiss: meshInteractiveDismiss,
            dismiss: dismiss
        )
    }

    private func pasteAddress() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string {
            model.recipientAddress = text.trimmingCharacters(in: .whitespacesAndNewlines)
            model.addressError = nil
        }
        #endif
    }

    @MainActor
    private func beginSendFromReview() {
        guard !model.isSending else { return }
        guard model.canSlideToSend else { return }

        Task { @MainActor in
            guard await authorizeSendIfNeeded() else { return }

            guard model.validateForSendExecution() else {
                if let message = model.sendExecutionErrorMessage {
                    path.append(SendRoute.failed(message: message))
                }
                return
            }

            let sendService = MeshBackgroundSendService.shared
            model.lockSendSlotForExecution()

            do {
                try await model.ensureSpendableBeforeExecution()
            } catch {
                path.append(
                    SendRoute.failed(message: SendErrorPresenter.message(for: error))
                )
                return
            }

            guard MeshNetworkSponsorship.isRelayConfigured else {
                path.append(
                    SendRoute.failed(
                        message: "Send service is temporarily unavailable. Please try again in a few minutes."
                    )
                )
                return
            }

            sendService.prepareForHandoff(model: model)
            path.append(SendRoute.sending)
            sendService.startHandoffForPendingSend(model: model)
        }
    }

    @MainActor
    private func authorizeSendIfNeeded() async -> Bool {
        guard MeshPasscodeStore.isBiometricEnabled else { return true }
        guard MeshBiometricAuth.isAvailable else {
            biometricAlertMessage = "\(MeshBiometricAuth.displayName) is unavailable on this device."
            return false
        }

        let result = await MeshBiometricAuth.authenticate(
            reason: "Confirm this send in Mesh"
        )

        switch result {
        case .success:
            return true
        case .cancelled:
            return false
        case .biometryLockout:
            biometricAlertMessage = "\(MeshBiometricAuth.displayName) is locked. Unlock your device and try again."
            return false
        case .unavailable:
            biometricAlertMessage = "\(MeshBiometricAuth.displayName) is unavailable on this device."
            return false
        case .failed:
            biometricAlertMessage = "\(MeshBiometricAuth.displayName) didn't match. Try again."
            return false
        }
    }
}
