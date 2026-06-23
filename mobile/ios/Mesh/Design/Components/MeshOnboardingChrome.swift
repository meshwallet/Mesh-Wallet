import SwiftUI

private struct MeshOnboardingBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var meshOnboardingBack: (() -> Void)? {
        get { self[MeshOnboardingBackKey.self] }
        set { self[MeshOnboardingBackKey.self] = newValue }
    }
}

/// Leading-edge strip that triggers onboarding back / pop (works when the nav bar is hidden).
private struct MeshOnboardingSwipeBackStrip: View {
    let onBack: (() -> Void)?

    private let edgeWidth: CGFloat = 28
    private let chromeTopInset: CGFloat = 120
    private let triggerTranslation: CGFloat = 64

    var body: some View {
        if onBack != nil {
            VStack(spacing: 0) {
                Color.clear.frame(height: chromeTopInset)
                Color.clear
                    .frame(width: edgeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(swipeBackGesture)
            }
            .frame(width: edgeWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(true)
        }
    }

    private var swipeBackGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded { value in
                guard value.translation.width >= triggerTranslation else { return }
                guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                onBack?()
            }
    }
}

extension View {
    /// Hides the system navigation bar; enables swipe-from-edge back when `onBack` is set.
    func meshOnboardingChrome(onBack: (() -> Void)? = nil) -> some View {
        toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .environment(\.meshOnboardingBack, onBack)
            .overlay(alignment: .leading) {
                MeshOnboardingSwipeBackStrip(onBack: onBack)
            }
            .meshSwipeBackEnabled()
    }

    /// Prefer `MeshEdgeDismissWrapper` at the `fullScreenCover` call site for modal dismiss.
    func meshModalChrome(onDismiss: @escaping () -> Void) -> some View {
        environment(\.meshOnboardingBack, onDismiss)
            .overlay(alignment: .leading) {
                MeshOnboardingSwipeBackStrip(onBack: onDismiss)
            }
    }
}
