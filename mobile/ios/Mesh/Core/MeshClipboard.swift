import Foundation
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

enum MeshClipboard {
    /// Reads plain text from the pasteboard. Must run on the main thread (UIKit requirement).
    static func pasteString(maxCharacters: Int = 12_000) -> String? {
        #if canImport(UIKit)
        guard let raw = UIPasteboard.general.string else { return nil }
        let capped = raw.count > maxCharacters ? String(raw.prefix(maxCharacters)) : raw
        let trimmed = capped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
        #else
        return nil
        #endif
    }

    /// Copies text to the system pasteboard. Returns whether the write succeeded.
    @discardableResult
    static func copy(_ text: String, expireAfter seconds: TimeInterval? = 120) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        #if canImport(UIKit)
        let pasteboard = UIPasteboard.general
        pasteboard.string = trimmed

        if let seconds, seconds > 0 {
            let expiration = Date().addingTimeInterval(seconds)
            pasteboard.setItems(
                [[UTType.plainText.identifier: trimmed]],
                options: [.expirationDate: expiration]
            )
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return true
        #else
        return false
        #endif
    }
}
