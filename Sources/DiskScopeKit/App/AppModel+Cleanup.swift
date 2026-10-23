import Foundation

extension AppModel {
    public func setStaleMonths(_ months: Int) {
        let clamped = min(max(months, 1), 120)
        UserDefaults.standard.set(clamped, forKey: AppSettingsKeys.staleMonths)
        cleanup.load()
    }

    public func loadCleanupSuggestionsIfNeeded() {
        cleanup.loadIfNeeded()
    }

    public func loadCleanupSuggestions() {
        cleanup.load()
    }
}
