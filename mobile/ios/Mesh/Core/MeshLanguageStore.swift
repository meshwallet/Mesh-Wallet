import Combine
import Foundation
import SwiftUI

/// Supported in-app languages. English is the development fallback.
enum MeshAppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"
    case vietnamese = "vi"
    case indonesian = "id"
    case spanish = "es"
    case arabic = "ar"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en"
        case .turkish: return "tr"
        case .vietnamese: return "vi"
        case .indonesian: return "id"
        case .spanish: return "es"
        case .arabic: return "ar"
        case .chineseSimplified: return "zh-Hans"
        }
    }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .turkish:
            return "Türkçe"
        case .vietnamese:
            return "Tiếng Việt"
        case .indonesian:
            return "Bahasa Indonesia"
        case .spanish:
            return "Español"
        case .arabic:
            return "العربية"
        case .chineseSimplified:
            return "简体中文"
        }
    }

    var usesRightToLeftLayout: Bool {
        self == .arabic
    }
}

@MainActor
final class MeshLanguageStore: ObservableObject {
    static let shared = MeshLanguageStore()

    private static let storageKey = "mesh.app.language"

    @Published private(set) var selected: MeshAppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? MeshAppLanguage.english.rawValue
        selected = MeshAppLanguage(rawValue: raw) ?? .english
        MeshL10n.apply(language: selected)
    }

    var locale: Locale {
        Locale(identifier: selected.localeIdentifier)
    }

    var localeIdentifier: String {
        selected.localeIdentifier
    }

    func setLanguage(_ language: MeshAppLanguage) {
        guard language != selected else { return }
        selected = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        MeshL10n.apply(language: language)
    }
}
