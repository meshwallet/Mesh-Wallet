#if canImport(UIKit)
import UIKit

final class MeshAppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillResignActive(_ application: UIApplication) {
        MeshPrivacyShield.presentIfAllowed()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        MeshPrivacyShield.dismiss()
        Task { @MainActor in
            MeshBackgroundSendService.shared.resumeProcessingSendsIfNeeded()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            MeshBackgroundSendService.shared.prepareForBackgroundContinuation()
        }
    }
}
#endif
