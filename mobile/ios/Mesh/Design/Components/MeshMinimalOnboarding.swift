import SwiftUI

// MARK: - Screen shell

struct MeshOnboardingScreen<Content: View, Footer: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer()
                    .meshScreenFooterButtons()
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Navigation

struct MeshNavigationHeader: View {
    var onBack: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var trailingText: String? = nil
    var showsBrandMark: Bool = false

    var body: some View {
        HStack {
            if let onClose {
                MeshChromeButton.close(action: onClose)
            } else if let onBack {
                MeshChromeButton.back(action: onBack)
            } else {
                Color.clear.frame(width: MeshTheme.Metrics.chromeButtonSize, height: MeshTheme.Metrics.chromeButtonSize)
            }

            Spacer(minLength: 0)

            if let trailingText {
                Text(trailingText)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
            } else if showsBrandMark {
                Text("M")
                    .font(MeshTheme.Typography.sans(size: 14, weight: .light))
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MeshTheme.Colors.border, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, MeshTheme.Metrics.screenPadding - 8)
        .zIndex(10)
    }
}

/// Send / Receive / modal flows — close row, then title (no overlap).
struct MeshFlowScreenHeader: View {
    let title: String
    let onClose: () -> Void
    var trailingText: String? = nil
    var usesBackButton: Bool = false
    var plainCloseButton: Bool = false

    @Environment(\.meshModalClose) private var meshModalClose
    @Environment(\.meshInteractiveDismiss) private var interactiveDismiss

    private var closeAction: () -> Void {
        if let meshModalClose { return meshModalClose }
        if let interactiveDismiss { return interactiveDismiss }
        return onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                if usesBackButton {
                    MeshChromeButton.back(
                        appearance: plainCloseButton ? .plain : .chrome,
                        action: onClose
                    )
                } else {
                    MeshChromeButton.close(
                        appearance: plainCloseButton ? .plain : .chrome,
                        action: closeAction
                    )
                }

                Spacer(minLength: 0)

                if let trailingText {
                    Text(trailingText)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, MeshTheme.Metrics.screenPadding - 8)
            .zIndex(10)

            Text(title)
                .font(MeshTheme.Typography.screenTitle())
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Typography

struct MeshTitleBlock: View {
    let title: String
    var subtitle: String? = nil
    var centered: Bool = false
    var brandGradientTitle: Bool = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 12) {
            Text(title)
                .font(brandGradientTitle ? MeshTheme.Typography.brandTitle() : MeshTheme.Typography.screenTitle())
                .foregroundStyle(brandGradientTitle ? AnyShapeStyle(MeshTheme.Colors.brandGradient) : AnyShapeStyle(MeshTheme.Colors.textPrimary))
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .lineSpacing(4)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

// MARK: - Import / option row

struct MeshOptionButton: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(MeshTheme.Typography.icon(size: 22, weight: .light))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(MeshTheme.Typography.sectionTitle())
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(MeshTheme.Typography.icon(size: 15, weight: .light))
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(MeshTheme.Colors.divider)
                    .frame(height: 1)
            }
        }
        .meshLiquidGlassButton(enabled: true, role: .regular, shape: .capsule)
        .modifier(MeshOptionPressStyle())
    }
}

private struct MeshOptionPressStyle: ViewModifier {
    func body(content: Content) -> some View {
        if MeshLiquidGlass.isSupported {
            content
        } else {
            content.buttonStyle(MeshOptionButtonStyle())
        }
    }
}

private struct MeshOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

// MARK: - Compact feature rows (welcome, etc.)

struct MeshFeaturePanel: View {
    let rows: [MeshFeatureRow.Model]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                MeshFeatureRow(model: row, showsDivider: index < rows.count - 1)
            }
        }
    }
}

struct MeshFeatureRow: View {
    struct Model: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String

        init(icon: String, title: String, value: String) {
            self.id = icon + title
            self.icon = icon
            self.title = title
            self.value = value
        }
    }

    let model: Model
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: model.icon)
                    .font(MeshTheme.Typography.icon(size: 20, weight: .light))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .frame(width: 28)

                Text(model.title)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)

                Spacer(minLength: 8)

                Text(model.value)
                    .font(MeshTheme.Typography.body())
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
            }
            .padding(.vertical, 16)

            if showsDivider {
                Rectangle()
                    .fill(MeshTheme.Colors.divider)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Bullet list

struct MeshBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(MeshTheme.Colors.textTertiary)
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                    Text(item)
                        .font(MeshTheme.Typography.secondary())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Input field

struct MeshInputPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .meshFieldSurface()
    }
}

struct MeshWalletNameField: View {
    @Binding var name: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wallet name")
                .font(MeshTheme.Typography.label())
                .foregroundStyle(MeshTheme.Colors.textSecondary)

            MeshInputPanel {
                TextField(placeholder, text: $name)
                    .font(MeshTheme.Typography.body())
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .meshTextInputAccent()
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            Text("Optional. Shown in your wallet list.")
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textTertiary)
        }
    }
}

struct MeshScreenHeader: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    var centered: Bool = false

    var body: some View {
        MeshTitleBlock(title: title, subtitle: subtitle, centered: centered)
    }
}

struct MeshSectionLabel: View {
    let text: String
    var body: some View { EmptyView() }
}
