import SwiftUI
import UIKit

/// Restores edge swipe-back when the navigation bar is hidden.
struct MeshSwipeBackEnabler: UIViewControllerRepresentable {
    let disabled: Bool

    init(disabled: Bool = false) {
        self.disabled = disabled
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let navigationController = resolveNavigationController(from: uiViewController) else { return }
            let gesture = navigationController.interactivePopGestureRecognizer
            if disabled {
                gesture?.isEnabled = false
            } else {
                gesture?.isEnabled = navigationController.viewControllers.count > 1
                gesture?.delegate = nil
            }
        }
    }

    private func resolveNavigationController(from controller: UIViewController) -> UINavigationController? {
        if let navigationController = controller.navigationController {
            return navigationController
        }
        var parent = controller.parent
        while let current = parent {
            if let navigationController = current as? UINavigationController {
                return navigationController
            }
            if let navigationController = current.navigationController {
                return navigationController
            }
            parent = current.parent
        }
        return findNavigationController(in: controller.view.window?.rootViewController)
    }

    private func findNavigationController(in root: UIViewController?) -> UINavigationController? {
        guard let root else { return nil }
        if let navigationController = root as? UINavigationController {
            return navigationController
        }
        for child in root.children {
            if let navigationController = findNavigationController(in: child) {
                return navigationController
            }
        }
        if let presented = root.presentedViewController,
           let navigationController = findNavigationController(in: presented) {
            return navigationController
        }
        return nil
    }
}

extension View {
    func meshSwipeBackEnabled() -> some View {
        background {
            MeshSwipeBackEnabler()
                .frame(width: 0, height: 0)
        }
    }

    /// Blocks NavigationStack interactive pop while a critical step runs.
    func meshNavigationPopDisabled(_ disabled: Bool) -> some View {
        background {
            MeshSwipeBackEnabler(disabled: disabled)
                .frame(width: 0, height: 0)
        }
    }
}
