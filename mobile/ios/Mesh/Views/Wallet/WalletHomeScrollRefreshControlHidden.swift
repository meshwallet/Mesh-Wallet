import SwiftUI
import UIKit

/// Wallet home scroll tuning: pull-to-refresh without visible UIRefreshControl spinner.
struct WalletHomeScrollBehavior: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = uiView.enclosingScrollView else { return }
            scrollView.alwaysBounceVertical = true
            scrollView.bounces = true
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.automaticallyAdjustsScrollIndicatorInsets = false
            if let refreshControl = scrollView.refreshControl {
                refreshControl.tintColor = .clear
                refreshControl.backgroundColor = .clear
            }
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var view: UIView? = self
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}

extension View {
    func walletHomeScrollBehavior() -> some View {
        background(WalletHomeScrollBehavior())
    }
}
