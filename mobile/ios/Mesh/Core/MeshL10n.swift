import Foundation

/// Resolves localized copy from `Localizable.xcstrings` using the active in-app language bundle.
enum MeshL10n {
    private static var bundle: Bundle = .main

    static func apply(language: MeshAppLanguage) {
        let code = language.localeIdentifier
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let localized = Bundle(path: path) {
            bundle = localized
        } else {
            bundle = .main
        }
    }

    static func tr(_ key: String, comment: String = "") -> String {
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        if value != key { return value }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: MeshLanguageStore.shared.locale, arguments: args)
    }
}
