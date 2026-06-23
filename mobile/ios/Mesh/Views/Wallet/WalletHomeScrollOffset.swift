import SwiftUI
import UIKit

enum WalletHomeScrollOffset {
    struct ViewportHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 800

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}

/// Geometry probe — iOS 17 fallback only (iOS 18 uses onScrollGeometryChange).
struct WalletHomeScrollOffsetProbe: View {
    @Binding var offset: CGFloat
    @State private var baseline: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    baseline = proxy.frame(in: .global).minY
                }
                .onChange(of: proxy.frame(in: .global).minY) { _, minY in
                    if baseline == nil {
                        baseline = minY
                    }
                    if let baseline {
                        offset = max(0, baseline - minY)
                    }
                }
        }
        .frame(height: 0)
    }
}

extension View {
    @ViewBuilder
    func walletHomeTracksScrollOffset(_ offset: Binding<CGFloat>) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                offset.wrappedValue = max(0, newValue)
            }
        } else {
            self.background(WalletHomeScrollOffsetTracker(offset: offset))
        }
    }
}

/// Список не обрезается по верхней границе ScrollView при прокрутке под hero.
extension View {
    @ViewBuilder
    func walletHomeScrollClipDisabled() -> some View {
        if #available(iOS 17.0, *) {
            scrollClipDisabled(true)
        } else {
            self
        }
    }

    /// Scroll content starts at screen top — matches hero overlay coordinates (no extra safe-area shift).
    @ViewBuilder
    func walletHomeScrollContentTopAligned() -> some View {
        if #available(iOS 17.0, *) {
            contentMargins(.top, 0, for: .scrollContent)
        } else {
            self
        }
    }
}

struct WalletHomeScrollOffsetTracker: UIViewRepresentable {
    @Binding var offset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset)
    }

    func makeUIView(context: Context) -> UIView {
        let view = TrackerAnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onMoveToWindow = { [weak coordinator = context.coordinator] view in
            coordinator?.attachFromView(view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let anchor = uiView as? TrackerAnchorView else { return }
        context.coordinator.attachFromView(anchor)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    final class Coordinator: NSObject {
        @Binding private var offset: CGFloat
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var isActive = true

        init(offset: Binding<CGFloat>) {
            _offset = offset
        }

        func invalidate() {
            isActive = false
            observation?.invalidate()
            observation = nil
            scrollView = nil
        }

        func attachFromView(_ view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.isActive else { return }
                guard let scrollView = view.enclosingScrollView else { return }
                self.attach(to: scrollView)
            }
        }

        func attach(to scrollView: UIScrollView) {
            guard isActive else { return }
            guard self.scrollView !== scrollView else {
                publishOffset(from: scrollView)
                return
            }
            observation?.invalidate()
            self.scrollView = scrollView
            observation = scrollView.observe(\.contentOffset, options: [.new, .initial]) { [weak self] sv, _ in
                self?.publishOffset(from: sv)
            }
        }

        private func publishOffset(from scrollView: UIScrollView) {
            guard isActive else { return }
            let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            offset = max(0, y)
        }
    }
}

private final class TrackerAnchorView: UIView {
    var onMoveToWindow: ((UIView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        onMoveToWindow?(self)
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
