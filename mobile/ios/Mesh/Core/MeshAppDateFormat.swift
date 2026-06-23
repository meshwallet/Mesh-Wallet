import Foundation

/// Dates/times formatted in the active in-app language (not the device locale).
enum MeshAppDateFormat {
    private static let languageStorageKey = "mesh.app.language"

    static var locale: Locale {
        let raw = UserDefaults.standard.string(forKey: languageStorageKey) ?? MeshAppLanguage.english.rawValue
        let code = MeshAppLanguage(rawValue: raw)?.localeIdentifier ?? MeshAppLanguage.english.localeIdentifier
        return Locale(identifier: code)
    }

    static func mediumDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
