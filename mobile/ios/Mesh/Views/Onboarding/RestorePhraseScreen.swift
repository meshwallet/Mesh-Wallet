import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RestorePhraseScreen: View {
    let onBack: () -> Void
    let onProceed: (PendingWalletDraft) -> Void

    @State private var walletName = ""
    @State private var phraseText = ""
    @State private var isImporting = false
    @State private var isPasting = false
    @State private var errorMessage: String?
    @State private var validationResult: ValidatResult = .invalidWordCount(expected: 12, actual: 0)
    @State private var validationTask: Task<Void, Never>?

    private var walletNamePlaceholder: String {
        MeshWalletRegistry.suggestedName(existingCount: MeshWalletRegistry.wallets.count)
    }

    private var canContinue: Bool {
        validationResult == .valid && !isImporting && !isPasting
    }

    private var validationMessage: String? {
        guard !phraseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch validationResult {
        case .valid:
            return "Phrase validated."
        case .invalidWordCount(_, let actual):
            return "Expected 12, 15, 18, 21, or 24 words. Current: \(actual)."
        case .invalidWord(let position, _):
            return "Word \(position) is not in the BIP-39 word list."
        case .invalidChecksum:
            return "Invalid checksum. Verify order and spelling."
        }
    }

    var body: some View {
        MeshOnboardingScreen {
            ZStack {
                VStack(spacing: 0) {
                    MeshNavigationHeader(onBack: onBack)
                        .padding(.top, 4)

                    MeshOnboardingScroll {
                        VStack(alignment: .leading, spacing: 24) {
                            MeshTitleBlock(
                                title: L10n.Onboarding.restorePhraseTitle,
                                subtitle: L10n.Onboarding.restorePhraseSubtitle
                            )

                            MeshWalletNameField(name: $walletName, placeholder: walletNamePlaceholder)

                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.Onboarding.restorePhraseTitle)
                                    .font(MeshTheme.Typography.label())
                                    .foregroundStyle(MeshTheme.Colors.textSecondary)

                                MeshInputPanel {
                                    MeshMultilineField(
                                        text: $phraseText,
                                        placeholder: L10n.Onboarding.restorePhrasePlaceholder,
                                        minHeight: 140
                                    )
                                }
                            }

                            HStack(spacing: 20) {
                                Button {
                                    pastePhrase()
                                } label: {
                                    if isPasting {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text(L10n.Common.paste)
                                        }
                                    } else {
                                        Text(L10n.Common.paste)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isPasting || isImporting)

                                Button("Clear") {
                                    phraseText = ""
                                }
                                .buttonStyle(.plain)
                                .disabled(isPasting || isImporting)
                            }
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textSecondary)

                            if let validationMessage {
                                Text(validationMessage)
                                    .font(MeshTheme.Typography.caption())
                                    .foregroundStyle(
                                        validationResult == .valid ? MeshTheme.Colors.success : Color.orange
                                    )
                            }

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

            }
        } footer: {
            MeshPrimaryButton(
                title: isImporting ? L10n.Common.generating : L10n.Onboarding.restorePhraseAction,
                isEnabled: canContinue
            ) {
                Task { await restoreWallet() }
            }
        }
        .onChange(of: phraseText) { _, newValue in
            guard !isPasting else { return }
            scheduleValidation(for: newValue)
        }
        .onAppear {
            scheduleValidation(for: phraseText)
        }
        .onDisappear {
            validationTask?.cancel()
        }
    }

    private func scheduleValidation(for text: String) {
        validationTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            validationResult = .invalidWordCount(expected: 12, actual: 0)
            return
        }

        let snapshot = text
        validationTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                let words = MeshWalletService.normalizePhrase(snapshot)
                return Valida.validateMnemonic(words: words)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                validationResult = result
            }
        }
    }

    private func pastePhrase() {
        guard !isPasting else { return }
        #if canImport(UIKit)
        isPasting = true
        MeshKeyboardDismiss.endEditing()

        Task { @MainActor in
            defer {
                isPasting = false
            }

            await Task.yield()

            guard let raw = MeshClipboard.pasteString() else { return }

            let sanitized = await Task.detached(priority: .userInitiated) {
                MeshWalletService.sanitizedPhrasePaste(raw)
            }.value

            phraseText = sanitized
            scheduleValidation(for: sanitized)
        }
        #endif
    }

    @MainActor
    private func restoreWallet() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        let words = MeshWalletService.normalizePhrase(phraseText)
        do {
            let trimmedName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty, MeshWalletRegistry.isWalletNameTaken(trimmedName) {
                errorMessage = L10n.Error.walletNameTaken
                return
            }

            let address = try MeshWalletService.importWallet(words: words)
            let draft = PendingWalletDraft(
                credential: .mnemonic(words: words),
                address: address,
                walletName: walletName,
                flow: .restored
            )
            onProceed(draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
