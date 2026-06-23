import CoreText
import SwiftUI
import UIKit

enum MeshFont {
    private static var didRegister = false

    private static let faces: [(resource: String, weight: Font.Weight)] = [
        ("Geist-Light", .light),
        ("Geist-Regular", .regular),
        ("Geist-Medium", .medium),
        ("Geist-SemiBold", .semibold),
        ("Geist-Bold", .bold)
    ]

    /// Call once at launch so `Font.custom` resolves bundled Geist files.
    static func register() {
        guard !didRegister else { return }
        didRegister = true

        for (resource, _) in faces {
            guard let url = bundleURL(for: resource) else {
                #if DEBUG
                print("MeshFont: missing \(resource).ttf in bundle")
                #endif
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            #if DEBUG
            if error != nil {
                print("MeshFont: failed to register \(resource).ttf")
            }
            #endif
        }

        #if DEBUG
        verifyFaces()
        #endif
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(faceName(for: weight), size: size, relativeTo: .body)
    }

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
        UIFont(name: faceName(for: weight), size: size)
            ?? UIFont.systemFont(ofSize: size, weight: uiWeight(for: weight))
    }

    private static func faceName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            return "Geist-Light"
        case .medium:
            return "Geist-Medium"
        case .semibold:
            return "Geist-SemiBold"
        case .bold, .heavy, .black:
            return "Geist-Bold"
        default:
            return "Geist-Regular"
        }
    }

    private static func uiWeight(for weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    private static func bundleURL(for resource: String) -> URL? {
        if let url = Bundle.main.url(forResource: resource, withExtension: "ttf") {
            return url
        }
        return Bundle.main.url(
            forResource: resource,
            withExtension: "ttf",
            subdirectory: "Fonts/Geist"
        )
    }

    #if DEBUG
    private static func verifyFaces() {
        for (resource, _) in faces {
            let name = resource
            if UIFont(name: name, size: 12) == nil {
                print("MeshFont: UIFont could not load PostScript name '\(name)'")
            }
        }
    }
    #endif
}
