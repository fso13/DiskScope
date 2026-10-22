import SwiftUI

enum AppSettingsKeys {
    static let appearance = "app.settings.appearance"
    static let confirmTrash = "app.settings.confirmTrash"
    static let language = "app.settings.language"
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системный"
        case .ru: return "Русский"
        case .en: return "Английский"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return Locale.current
        case .ru: return Locale(identifier: "ru_RU")
        case .en: return Locale(identifier: "en_US")
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
