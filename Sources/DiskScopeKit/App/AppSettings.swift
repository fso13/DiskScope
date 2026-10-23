import SwiftUI

public enum AppSettingsKeys {
    public static let appearance = "app.settings.appearance"
    public static let confirmTrash = "app.settings.confirmTrash"
    public static let language = "app.settings.language"
    public static let menuBarMonitor = "app.settings.menuBarMonitor"
    public static let menuBarDisplay = "app.settings.menuBarDisplay"
}

public extension Notification.Name {
    static let menuBarSettingsChanged = Notification.Name("DiskScopeMenuBarSettingsChanged")
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
