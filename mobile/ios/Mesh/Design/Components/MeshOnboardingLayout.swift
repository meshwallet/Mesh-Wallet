import SwiftUI

// MARK: - Environment

private struct MeshHorizontalInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 16
}

extension EnvironmentValues {
    var meshHorizontalInset: CGFloat {
        get { self[MeshHorizontalInsetKey.self] }
        set { self[MeshHorizontalInsetKey.self] = newValue }
    }
}

// MARK: - Insets (spacer gutters — reliable on all screen widths)

private struct MeshHorizontalGutterLayout<Content: View>: View {
    @Environment(\.meshHorizontalInset) private var inset
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: inset).frame(width: inset)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: inset).frame(width: inset)
        }
    }
}

extension View {
    func meshHorizontalGutters() -> some View {
        MeshHorizontalGutterLayout { self }
    }

    func meshScreenInsets(alignment: Alignment = .top) -> some View {
        meshHorizontalGutters()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

// MARK: - Scroll container

struct MeshOnboardingScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}
