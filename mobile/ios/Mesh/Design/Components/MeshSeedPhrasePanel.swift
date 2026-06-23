import SwiftUI

/// Numbered BIP-39 phrase in two columns (view / backup).
struct MeshSeedPhrasePanel: View {
    let words: [String]
    var footnote: String = L10n.Onboarding.recoverySubtitle
    var showsCopyAction: Bool = true

    @State private var didCopy = false

    private var phraseText: String {
        words.joined(separator: " ")
    }

    private var columnSplit: Int {
        (words.count + 1) / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            phraseCard

            Text(footnote)
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if showsCopyAction {
                MeshSecondaryButton(
                    title: didCopy ? L10n.Common.copied : L10n.Onboarding.recoveryCopy,
                    icon: didCopy ? "checkmark" : "doc.on.doc"
                ) {
                    copyPhrase()
                }
                .meshScreenFooterButtons()
                .padding(.top, 4)

                if didCopy {
                    Text(L10n.Onboarding.recoveryCopiedWarning)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.success)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var phraseCard: some View {
        HStack(alignment: .top, spacing: 20) {
            wordColumn(indices: words.indices.filter { $0 < columnSplit })
            wordColumn(indices: words.indices.filter { $0 >= columnSplit })
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MeshTheme.Colors.fieldFill,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func wordColumn(indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(MeshTheme.Typography.label())
                        .foregroundStyle(MeshTheme.Colors.textTertiary)
                        .frame(width: 18, alignment: .leading)

                    Text(words[index])
                        .font(MeshTheme.Typography.body())
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyPhrase() {
        guard MeshClipboard.copy(phraseText) else { return }
        didCopy = true

        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                didCopy = false
            }
        }
    }
}
