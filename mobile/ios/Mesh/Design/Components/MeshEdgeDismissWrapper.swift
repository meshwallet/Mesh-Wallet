import SwiftUI
import UIKit

private struct MeshInteractiveDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct MeshModalCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct MeshEdgeDismissDisabledKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension EnvironmentValues {
    var meshInteractiveDismiss: (() -> Void)? {
        get { self[MeshInteractiveDismissKey.self] }
        set { self[MeshInteractiveDismissKey.self] = newValue }
    }

    /// Animated slide-right close for wallet modals (Send / Receive / Privacy).
    var meshModalClose: (() -> Void)? {
        get { self[MeshModalCloseKey.self] }
        set { self[MeshModalCloseKey.self] = newValue }
    }
}

enum MeshModalPresentationEdge {
    /// Slides in from the right (Send, Receive, Settings).
    case trailing
    /// Slides in from the left (Privacy).
    case leading
}

struct MeshInteractivePresentFinishCommand: Equatable {
    enum Action: Equatable {
        case commit
        case cancel
    }

    let action: Action
    let velocityX: CGFloat
    let token: UUID
}

/// Overlays modal content on the current screen so swipe-back reveals the view underneath.
struct MeshEdgeDismissWrapper<Content: View>: View {
    @Binding var isPresented: Bool
    @State private var edgeDismissDisabled = false
    private let presentationEdge: MeshModalPresentationEdge
    private let interactiveHomeDragX: CGFloat
    private let isInteractivePresentDriving: Bool
    @Binding private var interactivePresentFinish: MeshInteractivePresentFinishCommand?
    private let content: Content

    init(
        isPresented: Binding<Bool>,
        presentationEdge: MeshModalPresentationEdge = .trailing,
        interactiveHomeDragX: CGFloat = 0,
        isInteractivePresentDriving: Bool = false,
        interactivePresentFinish: Binding<MeshInteractivePresentFinishCommand?> = .constant(nil),
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.presentationEdge = presentationEdge
        self.interactiveHomeDragX = interactiveHomeDragX
        self.isInteractivePresentDriving = isInteractivePresentDriving
        _interactivePresentFinish = interactivePresentFinish
        self.content = content()
    }

    var body: some View {
        MeshEdgeDismissScreenRepresentable(
            presentationEdge: presentationEdge,
            edgeDismissDisabled: edgeDismissDisabled,
            interactiveHomeDragX: interactiveHomeDragX,
            isInteractivePresentDriving: isInteractivePresentDriving,
            interactivePresentFinish: $interactivePresentFinish,
            onDismiss: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isPresented = false
                }
            },
            content: AnyView(content)
        )
        .onPreferenceChange(MeshEdgeDismissDisabledKey.self) { edgeDismissDisabled = $0 }
        .ignoresSafeArea()
    }
}

enum MeshModalClose {
    @MainActor
    static func perform(
        modalClose: (() -> Void)?,
        interactiveDismiss: (() -> Void)?,
        dismiss: DismissAction
    ) {
        if let modalClose {
            modalClose()
        } else if let interactiveDismiss {
            interactiveDismiss()
        } else {
            dismiss()
        }
    }
}

extension View {
    /// Blocks Mesh modal edge-swipe dismiss while a critical step runs (e.g. send handoff).
    func meshEdgeDismissDisabled(_ disabled: Bool) -> some View {
        preference(key: MeshEdgeDismissDisabledKey.self, value: disabled)
    }
}

private struct MeshEdgeDismissScreenRepresentable: UIViewControllerRepresentable {
    let presentationEdge: MeshModalPresentationEdge
    let edgeDismissDisabled: Bool
    let interactiveHomeDragX: CGFloat
    let isInteractivePresentDriving: Bool
    @Binding var interactivePresentFinish: MeshInteractivePresentFinishCommand?
    let onDismiss: () -> Void
    let content: AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> MeshEdgeDismissContainerController {
        let controller = MeshEdgeDismissContainerController(
            presentationEdge: presentationEdge,
            rootView: context.coordinator.wrap(content),
            onDismiss: onDismiss
        )
        controller.isInteractivePresentDriving = isInteractivePresentDriving
        if isInteractivePresentDriving {
            controller.updateInteractivePresentHomeDragX(interactiveHomeDragX)
        }
        context.coordinator.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: MeshEdgeDismissContainerController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.controller = uiViewController
        uiViewController.onDismiss = onDismiss
        uiViewController.setEdgeDismissDisabled(edgeDismissDisabled)
        uiViewController.isInteractivePresentDriving = isInteractivePresentDriving
        if isInteractivePresentDriving {
            uiViewController.updateInteractivePresentHomeDragX(interactiveHomeDragX)
        }
        context.coordinator.applyInteractivePresentFinishIfNeeded(
            interactivePresentFinish,
            controller: uiViewController
        )
        // Do not replace hosting.rootView here — WalletHomeView re-renders (balance,
        // scroll) would reset @State and re-run wallet creation.
    }

    final class Coordinator {
        var onDismiss: () -> Void
        weak var controller: MeshEdgeDismissContainerController?
        private var lastInteractiveFinishToken: UUID?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func applyInteractivePresentFinishIfNeeded(
            _ command: MeshInteractivePresentFinishCommand?,
            controller: MeshEdgeDismissContainerController
        ) {
            guard let command else { return }
            guard command.token != lastInteractiveFinishToken else { return }
            lastInteractiveFinishToken = command.token
            controller.finishInteractivePresentFromHome(
                commit: command.action == .commit,
                velocityX: command.velocityX
            )
        }

        func wrap(_ content: AnyView) -> AnyView {
            let animatedClose: () -> Void = { [weak self] in
                self?.controller?.performAnimatedDismiss()
            }
            return AnyView(
                content
                    .environment(\.meshInteractiveDismiss, animatedClose)
                    .environment(\.meshModalClose, animatedClose)
            )
        }
    }
}

final class MeshEdgeDismissContainerController: UIViewController, UIGestureRecognizerDelegate {
    var onDismiss: () -> Void
    private let presentationEdge: MeshModalPresentationEdge
    private var hosting: UIHostingController<AnyView>
    private let contentContainer = UIView()
    private let edgeCaptureView = UIView()

    private let dismissDistanceRatio: CGFloat = 0.33
    private let dismissVelocityThreshold: CGFloat = 700
    private let presentSpringDuration: TimeInterval = 0.42
    private let presentSpringDamping: CGFloat = 0.9
    private var didRunPresentAnimation = false
    var isInteractivePresentDriving = false
    private var interactiveHomeDragXSnapshot: CGFloat = 0
    private var edgeDismissDisabled = false
    private var dismissGestures: [UIGestureRecognizer] = []
    /// Leading/top band reserved for close/back — dismiss pans must not steal taps here.
    private let chromeHitZoneWidth: CGFloat = 120
    private let chromeHitZoneHeight: CGFloat = 120

    init(
        presentationEdge: MeshModalPresentationEdge,
        rootView: AnyView,
        onDismiss: @escaping () -> Void
    ) {
        self.presentationEdge = presentationEdge
        self.onDismiss = onDismiss
        self.hosting = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRootView(_ rootView: AnyView) {
        hosting.rootView = rootView
    }

    func setEdgeDismissDisabled(_ disabled: Bool) {
        guard edgeDismissDisabled != disabled else { return }
        edgeDismissDisabled = disabled
        dismissGestures.forEach { $0.isEnabled = !disabled }
        if disabled, contentContainer.transform.tx != 0 {
            cancelInteractiveDismiss()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false

        contentContainer.backgroundColor = .black
        contentContainer.layer.masksToBounds = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        contentContainer.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        hosting.didMove(toParent: self)

        installDismissGestures()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !didRunPresentAnimation else { return }
        let width = max(view.bounds.width, UIScreen.main.bounds.width)
        if isInteractivePresentDriving {
            let transform = presentTransformForHomeDrag(interactiveHomeDragXSnapshot, width: width)
            contentContainer.transform = transform
            updateShadow(progress: presentProgressForHomeDrag(interactiveHomeDragXSnapshot, width: width))
        } else {
            contentContainer.transform = offscreenTransform(width: width)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didRunPresentAnimation else { return }
        didRunPresentAnimation = true
        guard !isInteractivePresentDriving else { return }
        runPresentAnimation()
    }

    func updateInteractivePresentHomeDragX(_ homeDragX: CGFloat) {
        interactiveHomeDragXSnapshot = homeDragX
        let width = max(view.bounds.width, UIScreen.main.bounds.width)
        if !didRunPresentAnimation {
            didRunPresentAnimation = true
        }
        let transform = presentTransformForHomeDrag(homeDragX, width: width)
        contentContainer.transform = transform
        let progress = presentProgressForHomeDrag(homeDragX, width: width)
        updateShadow(progress: progress)
    }

    func finishInteractivePresentFromHome(commit: Bool, velocityX: CGFloat) {
        if commit {
            UIView.animate(
                withDuration: presentSpringDuration,
                delay: 0,
                usingSpringWithDamping: presentSpringDamping,
                initialSpringVelocity: min(1.2, abs(velocityX) / 900),
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                self.contentContainer.transform = .identity
                self.contentContainer.layer.shadowOpacity = 0
            }
        } else {
            let width = max(view.bounds.width, 1)
            let targetX = presentationEdge == .leading ? -width : width
            let velocityMagnitude = max(abs(velocityX), 900)
            let currentX = contentContainer.transform.tx
            let remaining = max(0, abs(targetX - currentX))
            let duration = min(presentSpringDuration, max(0.14, TimeInterval(remaining / velocityMagnitude)))

            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                self.contentContainer.transform = CGAffineTransform(translationX: targetX, y: 0)
                self.updateShadow(progress: 0)
            } completion: { _ in
                self.onDismiss()
            }
        }
    }

    private func presentTransformForHomeDrag(_ homeDragX: CGFloat, width: CGFloat) -> CGAffineTransform {
        switch presentationEdge {
        case .leading:
            let clamped = min(max(homeDragX, 0), width)
            return CGAffineTransform(translationX: -width + clamped, y: 0)
        case .trailing:
            let clamped = max(min(homeDragX, 0), -width)
            return CGAffineTransform(translationX: width + clamped, y: 0)
        }
    }

    private func presentProgressForHomeDrag(_ homeDragX: CGFloat, width: CGFloat) -> CGFloat {
        switch presentationEdge {
        case .leading:
            return min(1, max(0, homeDragX) / width)
        case .trailing:
            return min(1, max(0, -homeDragX) / width)
        }
    }

    private func runPresentAnimation() {
        let width = max(view.bounds.width, UIScreen.main.bounds.width)
        contentContainer.transform = offscreenTransform(width: width)
        updateShadow(progress: 0.12)

        UIView.animate(
            withDuration: presentSpringDuration,
            delay: 0,
            usingSpringWithDamping: presentSpringDamping,
            initialSpringVelocity: 0.45,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.contentContainer.transform = .identity
            self.contentContainer.layer.shadowOpacity = 0
        }
    }

    private func installDismissGestures() {
        let screenEdge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        screenEdge.edges = presentationEdge == .leading ? .right : .left
        screenEdge.delegate = self
        screenEdge.cancelsTouchesInView = false
        contentContainer.addGestureRecognizer(screenEdge)

        edgeCaptureView.backgroundColor = .clear
        edgeCaptureView.isUserInteractionEnabled = true
        edgeCaptureView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(edgeCaptureView)
        if presentationEdge == .leading {
            NSLayoutConstraint.activate([
                edgeCaptureView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                edgeCaptureView.topAnchor.constraint(equalTo: contentContainer.safeAreaLayoutGuide.topAnchor, constant: chromeHitZoneHeight),
                edgeCaptureView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                edgeCaptureView.widthAnchor.constraint(equalToConstant: 24)
            ])
        } else {
            NSLayoutConstraint.activate([
                edgeCaptureView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                edgeCaptureView.topAnchor.constraint(equalTo: contentContainer.safeAreaLayoutGuide.topAnchor, constant: chromeHitZoneHeight),
                edgeCaptureView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                edgeCaptureView.widthAnchor.constraint(equalToConstant: 24)
            ])
        }

        let strip = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        strip.delegate = self
        strip.cancelsTouchesInView = false
        edgeCaptureView.addGestureRecognizer(strip)

        dismissGestures = [screenEdge, strip]
    }

    private func offscreenTransform(width: CGFloat) -> CGAffineTransform {
        switch presentationEdge {
        case .trailing:
            return CGAffineTransform(translationX: width, y: 0)
        case .leading:
            return CGAffineTransform(translationX: -width, y: 0)
        }
    }

    private func isTouchInChromeHitZone(_ touch: UITouch) -> Bool {
        let point = touch.location(in: contentContainer)
        return point.x < chromeHitZoneWidth && point.y < chromeHitZoneHeight
    }

    @objc private func handleDismissPan(_ gesture: UIGestureRecognizer) {
        guard !edgeDismissDisabled else { return }
        guard let pan = gesture as? UIPanGestureRecognizer else { return }
        let width = max(view.bounds.width, 1)
        let rawTranslationX = pan.translation(in: view).x
        let translationX: CGFloat
        let progress: CGFloat
        switch presentationEdge {
        case .trailing:
            translationX = max(0, rawTranslationX)
            progress = min(1, translationX / width)
        case .leading:
            translationX = min(0, rawTranslationX)
            progress = min(1, abs(translationX) / width)
        }

        switch pan.state {
        case .began, .changed:
            contentContainer.transform = CGAffineTransform(translationX: translationX, y: 0)
            updateShadow(progress: progress)
        case .ended, .cancelled:
            let velocityX = pan.velocity(in: view).x
            let shouldDismiss: Bool
            switch presentationEdge {
            case .trailing:
                shouldDismiss = translationX > width * dismissDistanceRatio
                    || velocityX > dismissVelocityThreshold
            case .leading:
                shouldDismiss = abs(translationX) > width * dismissDistanceRatio
                    || velocityX < -dismissVelocityThreshold
            }
            if shouldDismiss {
                finishInteractiveDismiss(velocityX: velocityX)
            } else {
                cancelInteractiveDismiss()
            }
        default:
            break
        }
    }

    private func updateShadow(progress: CGFloat) {
        contentContainer.layer.shadowColor = UIColor.black.cgColor
        contentContainer.layer.shadowOpacity = Float(min(0.28, progress * 0.35))
        contentContainer.layer.shadowRadius = 18
        let shadowX: CGFloat = presentationEdge == .leading ? 6 : -6
        contentContainer.layer.shadowOffset = CGSize(width: shadowX, height: 0)
    }

    func performAnimatedDismiss() {
        guard !edgeDismissDisabled else { return }
        finishInteractiveDismiss(velocityX: dismissVelocityThreshold)
    }

    private func finishInteractiveDismiss(velocityX: CGFloat) {
        let width = max(view.bounds.width, 1)
        let currentX = contentContainer.transform.tx
        let targetX = presentationEdge == .leading ? -width : width
        let remaining = max(0, abs(targetX - currentX))
        let velocityMagnitude = max(abs(velocityX), 900)
        let duration = min(presentSpringDuration, max(0.14, TimeInterval(remaining / velocityMagnitude)))

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.contentContainer.transform = CGAffineTransform(translationX: targetX, y: 0)
            self.updateShadow(progress: 0)
        } completion: { _ in
            self.onDismiss()
        }
    }

    private func cancelInteractiveDismiss() {
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.6,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.contentContainer.transform = .identity
            self.contentContainer.layer.shadowOpacity = 0
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if isTouchInChromeHitZone(touch) {
            return false
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !edgeDismissDisabled else { return false }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: contentContainer)
        if abs(velocity.x) + abs(velocity.y) < 8 { return true }
        return abs(velocity.x) >= abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
