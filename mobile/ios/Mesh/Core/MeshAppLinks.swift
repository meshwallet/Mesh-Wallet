import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum MeshAppLinks {
    static let contactPage = URL(string: "https://meshwallet.app/support")
    static let termsPage = URL(string: "https://meshone.app/terms-and-conditions")
    static let privacyPage = URL(string: "https://meshone.app/privacy-policy")

    static func open(_ url: URL?) {
        guard let url else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    static func openContactPage() {
        open(contactPage)
    }
}
