import SwiftUI

struct MeshRenameWalletSheet: View {
    let walletID: String
    let currentName: String
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var nameError: String?

    init(
        walletID: String,
        currentName: String,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.walletID = walletID
        self.currentName = currentName
        self.onSaved = onSaved
        self.onCancel = onCancel
        _name = State(initialValue: currentName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
            && trimmedName != currentName
            && nameError == nil
            && !MeshWalletRegistry.isWalletNameTaken(trimmedName, excludingWalletID: walletID)
    }

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Cancel", action: onCancel)
                            .buttonStyle(.plain)
                            .font(MeshTheme.Typography.secondary())
                            .foregroundStyle(MeshTheme.Colors.textSecondary)
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)

                    Spacer(minLength: 16)

                    MeshTitleBlock(
                        title: "Rename wallet",
                        subtitle: "Shown in your wallet list.",
                        centered: true
                    )
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)

                    MeshWalletNameField(
                        name: $name,
                        placeholder: MeshWalletRegistry.suggestedName(
                            existingCount: max(0, MeshWalletRegistry.wallets.count - 1)
                        )
                    )
                    .onChange(of: name) { _, _ in
                        validateName()
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 28)

                    if let nameError {
                        Text(nameError)
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 120)
                }
            }
            .scrollDismissesKeyboard(.never)

            VStack {
                Spacer()
                MeshPrimaryButton(title: "Save", isEnabled: canSave) {
                    guard MeshWalletRegistry.updateWalletName(id: walletID, name: trimmedName) else {
                        nameError = L10n.Error.walletNameTaken
                        return
                    }
                    onSaved()
                }
                .meshScreenFooterButtons()
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .meshDismissKeyboardOnSwipeDown()
        .onAppear {
            validateName()
        }
    }

    private func validateName() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else {
            nameError = nil
            return
        }
        if MeshWalletRegistry.isWalletNameTaken(trimmed, excludingWalletID: walletID) {
            nameError = L10n.Error.walletNameTaken
        } else {
            nameError = nil
        }
    }
}
