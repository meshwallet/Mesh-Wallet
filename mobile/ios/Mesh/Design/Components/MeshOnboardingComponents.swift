import SwiftUI

// Minimal onboarding UI lives in `MeshMinimalOnboarding.swift`.
// Legacy row types for backup / restore flows.

struct MeshSpecRow: View {
    var icon: String? = nil
    let title: String
    let subtitle: String
    var showsDivider: Bool = true
    var compact: Bool = false
    var tight: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(MeshTheme.Typography.icon(size: 18, weight: .light))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(MeshTheme.Typography.sectionTitle())
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, tight ? 10 : 12)

            if showsDivider {
                Rectangle()
                    .fill(MeshTheme.Colors.divider)
                    .frame(height: 1)
            }
        }
    }
}

struct MeshSpecGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .meshSurfacePanel()
    }
}

struct MeshOptionRow: View {
    var icon: String? = nil
    let title: String
    var detail: String? = nil
    var showsDivider: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MeshSpecRow(icon: icon, title: title, subtitle: detail ?? "", showsDivider: showsDivider, tight: true)
        }
        .meshLiquidGlassButton(enabled: true, role: .regular, shape: .capsule)
    }
}

struct MeshOptionGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .meshSurfacePanel()
    }
}

struct MeshRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct MeshStaggeredAppear: ViewModifier {
    let index: Int
    func body(content: Content) -> some View { content }
}

extension View {
    func meshStaggeredAppear(index: Int) -> some View {
        modifier(MeshStaggeredAppear(index: index))
    }
}

