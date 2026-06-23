import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RestorePrivateKeyScreen: View {
    let onBack: () -> Void
    let onProceed: (PendingWalletDraft) -> Void

    @State private var walletName = ""
    @State private var privateKeyText = ""
    @State private var isImporting = false
    @State private var isPasting = false
    @State private var errorMessage: String?

    private var walletNamePlaceholder: String {
        MeshWalletRegistry.suggestedName(existingCount: MeshWalletRegistry.wallets.count)
    }

    private var normalizedKey: String {
        MeshWalletService.normalizePrivateKeyInput(privateKeyText)
    }

    private var isValidKey: Bool {
        MeshWalletService.isValidPrivateKeyFormat(privateKeyText)
    }

    private var canContinue: Bool {
        isValidKey && !isImporting && !isPasting
    }

    private var validationMessage: String? {
        guard !privateKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return isValidKey
            ? "Private key validated."
            : "Enter 64 hex characters (32 bytes). Optional 0x prefix."
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
                                title: L10n.Onboarding.restoreKeyTitle,
                                subtitle: L10n.Onboarding.restoreKeySubtitle
                            )

                            MeshWalletNameField(name: $walletName, placeholder: walletNamePlaceholder)

                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.Onboarding.restoreKeyTitle)
                                    .font(MeshTheme.Typography.label())
                                    .foregroundStyle(MeshTheme.Colors.textSecondary)

                                MeshInputPanel {
                                    MeshMultilineField(
                                        text: $privateKeyText,
                                        placeholder: L10n.Onboarding.restoreKeyPlaceholder,
                                        isMonospaced: true,
                                        minHeight: 100
                                    )
                                }
                            }

                            HStack(spacing: 20) {
                                Button {
                                    pasteKey()
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

                                Button("Clear") { privateKeyText = "" }
                                    .buttonStyle(.plain)
                                    .disabled(isPasting || isImporting)
                            }
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textSecondary)

                            if let validationMessage {
                                Text(validationMessage)
                                    .font(MeshTheme.Typography.caption())
                                    .foregroundStyle(
                                        isValidKey ? MeshTheme.Colors.success : Color.orange
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
            MeshPrimaryButton(title: isImporting ? L10n.Common.generating : L10n.Onboarding.restoreKeyAction, isEnabled: canContinue) {
                Task { await restoreWallet() }
            }
        }
    }

    private func pasteKey() {
        guard !isPasting else { return }
        #if canImport(UIKit)
        isPasting = true
        MeshKeyboardDismiss.endEditing()

        Task { @MainActor in
            defer {
                isPasting = false
            }

            await Task.yield()

            guard let raw = MeshClipboard.pasteString(maxCharacters: 256) else { return }

            let normalized = await Task.detached(priority: .userInitiated) {
                MeshWalletService.normalizePrivateKeyInput(raw)
            }.value

            privateKeyText = normalized
        }
        #endif
    }

    @MainActor
    private func restoreWallet() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let trimmedName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty, MeshWalletRegistry.isWalletNameTaken(trimmedName) {
                errorMessage = L10n.Error.walletNameTaken
                return
            }

            let address = try MeshWalletService.importPrivateKey(privateKeyText)
            let draft = PendingWalletDraft(
                credential: .privateKey(hex: normalizedKey),
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
