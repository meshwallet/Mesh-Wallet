import SwiftUI

/// Screen-size–aware layout constants.
enum MeshLayout {
    /// Horizontal gutter from screen width (Pro / Max / SE).
    static func horizontalInset(width: CGFloat) -> CGFloat {
        switch width {
        case ..<360:
            return 12
        case ..<390:
            return 14
        case ..<420:
            return 16
        default:
            return 18
        }
    }
}

private struct MeshScreenWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 390

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Publishes root width for adaptive horizontal insets.
    func meshPublishScreenWidth(_ width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: MeshScreenWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(MeshScreenWidthKey.self) { width.wrappedValue = $0 }
    }
}
