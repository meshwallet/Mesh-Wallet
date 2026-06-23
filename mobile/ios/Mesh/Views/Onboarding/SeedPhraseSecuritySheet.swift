import SwiftUI

struct SeedPhraseSecuritySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<Int> = []
    let onContinue: () -> Void

    private let items: [String] = [
        "Only you know this secret phrase.",
        "This secret phrase was NOT given to you by anyone, e.g. a company representative.",
        "If someone else has seen it, they can steal your funds"
    ]

    private var allChecked: Bool {
        checked.count == items.count
    }

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                MeshNavigationHeader(onClose: { dismiss() })
                    .padding(.top, 4)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroImage
                            .padding(.top, 8)

                        Text("Check your secret phrase is safe")
                            .font(MeshTheme.Typography.screenTitle())
                            .foregroundStyle(MeshTheme.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                            .padding(.top, 28)

                        VStack(spacing: 12) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                                securityCard(index: index, text: text)
                            }
                        }
                        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)

                MeshPrimaryButton(title: "Continue", isEnabled: allChecked) {
                    dismiss()
                    onContinue()
                }
                .meshScreenFooterButtons()
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.bottom, 16)
            }
        }
        .presentationBackground(MeshTheme.Colors.background)
    }

    private var heroImage: some View {
        Image("SecretPhraseSecurityHero")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 280)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func securityCard(index: Int, text: String) -> some View {
        let isChecked = checked.contains(index)

        return Button {
            if isChecked {
                checked.remove(index)
            } else {
                checked.insert(index)
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(MeshTheme.Typography.icon(size: 22, weight: .regular))
                    .foregroundStyle(isChecked ? MeshTheme.Colors.success : MeshTheme.Colors.textTertiary)
                    .padding(.top, 1)

                Text(text)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(MeshTheme.Colors.fieldFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
