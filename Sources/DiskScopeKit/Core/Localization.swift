import Foundation

public enum L10n {
    public static var isEnglish: Bool {
        switch UserDefaults.standard.string(forKey: "app.settings.language") {
        case "en": return true
        case "ru": return false
        default:
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return false
            }
            return Locale.preferredLanguages.first?.hasPrefix("en") == true
        }
    }

    public static var locale: Locale {
        switch UserDefaults.standard.string(forKey: "app.settings.language") {
        case "en": return Locale(identifier: "en_US")
        case "ru": return Locale(identifier: "ru_RU")
        default: return Locale.current
        }
    }

    /// Localizes model-level strings (toasts, errors, plurals) using the app setting.
    public static func t(_ key: String) -> String {
        isEnglish ? english(key) : key
    }

    public static func english(_ key: String) -> String {
        for bundle in englishBundles {
            let value = bundle.localizedString(forKey: key, value: "", table: nil)
            if !value.isEmpty { return value }
        }
        return key
    }

    private static var englishBundles: [Bundle] {
        var result: [Bundle] = []
        if let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            result.append(bundle)
        }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            result.append(bundle)
        }
        var bases: [URL] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
        ].compactMap { $0 }
        for host in Bundle.allBundles + Bundle.allFrameworks {
            bases.append(host.bundleURL)
            bases.append(host.bundleURL.appendingPathComponent("Contents/Resources"))
            if let resource = host.resourceURL { bases.append(resource) }
        }
        var seen: Set<String> = []
        for base in bases where seen.insert(base.path).inserted {
            let url = base.appendingPathComponent("DiskScope_DiskScopeKit.bundle")
            if let bundle = Bundle(url: url),
               let path = bundle.path(forResource: "en", ofType: "lproj"),
               let english = Bundle(path: path) {
                result.append(english)
            }
        }
        return result
    }
}
