import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MeshKeyboardDismiss {
#if canImport(UIKit)
    static func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
#endif
}

extension View {
    /// Keeps scroll content stable while editing — interactive keyboard dismiss shifts insets and jerks the scroll view.
    func meshScrollDismissesKeyboard() -> some View {
        scrollDismissesKeyboard(.never)
    }

    /// Dismisses the keyboard on a downward swipe without resizing scroll content.
    func meshDismissKeyboardOnSwipeDown(minimumDistance: CGFloat = 20) -> some View {
#if canImport(UIKit)
        simultaneousGesture(
            DragGesture(minimumDistance: minimumDistance, coordinateSpace: .local)
                .onEnded { value in
                    let vertical = value.translation.height
                    let horizontal = value.translation.width
                    guard vertical > 12, abs(vertical) > abs(horizontal) else { return }
                    MeshKeyboardDismiss.endEditing()
                }
        )
#else
        self
#endif
    }
}
