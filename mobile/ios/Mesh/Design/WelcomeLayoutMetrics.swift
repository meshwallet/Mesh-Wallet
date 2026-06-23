import SwiftUI

/// Welcome screen — proportional zones, large CTAs.
struct WelcomeLayoutMetrics {
    let titleSize: CGFloat
    let buttonSize: CGFloat

    init(availableHeight: CGFloat) {
        if availableHeight >= 820 {
            titleSize = 46
            buttonSize = 76
        } else if availableHeight >= 740 {
            titleSize = 42
            buttonSize = 72
        } else {
            titleSize = 38
            buttonSize = 66
        }
    }
}

private struct WelcomeAvailableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 780

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func meshWelcomeHeightReader(_ height: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WelcomeAvailableHeightKey.self,
                    value: proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
                )
            }
        }
        .onPreferenceChange(WelcomeAvailableHeightKey.self) { height.wrappedValue = $0 }
    }
}
