import SwiftUI

// MARK: - Section chrome (no fill — hairlines only)

struct MeshActivitySectionHeader: View {
    enum Style {
        case `default`
        case home
    }

    let title: String
    var style: Style = .default

    private var titleColor: Color {
        switch style {
        case .default:
            MeshTheme.Colors.textTertiary
        case .home:
            MeshTheme.Colors.homeTextSecondary.opacity(0.72)
        }
    }

    var body: some View {
        Text(title)
            .font(MeshTheme.Typography.sans(size: 13, weight: .medium))
            .foregroundStyle(titleColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, style == .home ? 2 : 6)
            .padding(.bottom, 4)
    }
}

struct MeshHairlineDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(MeshTheme.Colors.divider)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

struct MeshTransactionDetailField: View {
    let icon: String
    let title: String
    let value: String
    var isMonospace: Bool = false
    var truncateMiddle: Bool = false
    var expandable: Bool = false
    var onCopy: (() -> Void)?
    var copied: Bool = false

    @State private var showsFullText = false

    var body: some View {
        let content = fieldContent

        if expandable, !value.isEmpty {
            Button {
                showsFullText = true
            } label: {
                content
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showsFullText) {
                fullTextSheet
            }
        } else {
            content
        }
    }

    private var fieldContent: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(MeshTheme.Typography.icon(size: 18, weight: .light))
                .foregroundStyle(MeshTheme.Colors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title.uppercased())
                        .font(MeshTheme.Typography.sans(size: 11, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(MeshTheme.Colors.textTertiary)
                    if expandable, !value.isEmpty {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MeshTheme.Colors.textTertiary)
                    }
                }
                Text(value.isEmpty ? "—" : value)
                    .font(
                        isMonospace
                            ? MeshTheme.Typography.sans(size: 14, weight: .regular)
                            : MeshTheme.Typography.sans(size: 16, weight: .regular)
                    )
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(truncateMiddle ? 1 : (expandable ? 4 : 2))
                    .truncationMode(truncateMiddle ? .middle : .tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onCopy, !value.isEmpty {
                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "square.on.square")
                        .font(MeshTheme.Typography.icon(size: 16, weight: .light))
                        .foregroundStyle(copied ? MeshTheme.Colors.success : MeshTheme.Colors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .meshLiquidGlassButton(enabled: true, role: .regular, shape: .circle)
            }
        }
        .padding(.vertical, 18)
    }

    private var fullTextSheet: some View {
        NavigationStack {
            ScrollView {
                Text(value)
                    .font(MeshTheme.Typography.sans(size: 16, weight: .regular))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MeshTheme.Metrics.screenPadding)
            }
            .background(MeshSelectWalletSheetBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.done) {
                        showsFullText = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct MeshInlineStatsRow: View {
    let metrics: [(value: String, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(MeshTheme.Colors.divider)
                        .frame(width: 1, height: 32)
                }
                VStack(spacing: 5) {
                    Text(metric.value)
                        .font(MeshTheme.Typography.sans(size: 22, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    Text(metric.label.uppercased())
                        .font(MeshTheme.Typography.sans(size: 10, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(MeshTheme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }
}

enum MeshTransactionVisuals {
    static func accentColor(incoming: Bool) -> Color {
        incoming ? MeshTheme.Colors.success : MeshTheme.Colors.textPrimary
    }

    /// Soft glow from the top of the detail sheet through the hero area.
    static func heroGlow(incoming: Bool) -> RadialGradient {
        let accent = accentColor(incoming: incoming)
        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: accent.opacity(0.24), location: 0),
                .init(color: accent.opacity(0.12), location: 0.35),
                .init(color: accent.opacity(0.04), location: 0.65),
                .init(color: Color.clear, location: 1),
            ]),
            center: UnitPoint(x: 0.5, y: 0.08),
            startRadius: 0,
            endRadius: 340
        )
    }
}
