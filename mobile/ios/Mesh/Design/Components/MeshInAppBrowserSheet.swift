import SwiftUI
import SafariServices

/// In-app browser for external links (keeps user inside Mesh).
struct MeshInAppBrowserSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor.white
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension View {
    /// Presents `MeshInAppBrowserSheet` when `url` is non-nil (same pattern as View on Tronscan).
    func meshInAppBrowserSheet(url: Binding<URL?>) -> some View {
        sheet(isPresented: Binding(
            get: { url.wrappedValue != nil },
            set: { if !$0 { url.wrappedValue = nil } }
        )) {
            if let browserURL = url.wrappedValue {
                MeshInAppBrowserSheet(url: browserURL)
                    .ignoresSafeArea()
            }
        }
    }
}
