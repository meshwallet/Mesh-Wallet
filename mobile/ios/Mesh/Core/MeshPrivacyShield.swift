#if canImport(UIKit)
import SwiftUI
import UIKit

/// App-switcher privacy overlay — must attach on `willResignActive` (before iOS snapshots the window).
@MainActor
enum MeshPrivacyShield {
    private static let overlayTag = 0x4D_65_73_68

    static var isSuppressed = false
    static var hasBeenActive = false

    static var canPresent: Bool {
        hasBeenActive && !isSuppressed
    }

    static func presentIfAllowed() {
        guard canPresent else { return }
        guard let window = keyWindow else { return }
        guard window.viewWithTag(overlayTag) == nil else { return }

        let bounds = window.bounds

        let container = UIView(frame: bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.tag = overlayTag
        container.isUserInteractionEnabled = false

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(blur)

        let dim = UIView(frame: bounds)
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(dim)

        if let image = UIImage(named: "IconPng") {
            let icon = UIImageView(image: image)
            icon.contentMode = .scaleAspectFit
            let side = bounds.width * 0.5
            icon.frame = CGRect(
                x: (bounds.width - side) / 2,
                y: (bounds.height - side) / 2,
                width: side,
                height: side
            )
            icon.autoresizingMask = [
                .flexibleLeftMargin,
                .flexibleRightMargin,
                .flexibleTopMargin,
                .flexibleBottomMargin,
            ]
            container.addSubview(icon)
        }

        window.addSubview(container)
    }

    static func dismiss() {
        keyWindow?.viewWithTag(overlayTag)?.removeFromSuperview()
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
#endif
