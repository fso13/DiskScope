import Foundation

extension AppModel {
    public func setStaleMonths(_ months: Int) {
        let clamped = min(max(months, 1), 120)
        UserDefaults.standard.set(clamped, forKey: AppSettingsKeys.staleMonths)
        loadCleanupSuggestions()
    }

    public func loadCleanupSuggestionsIfNeeded() {
        guard let tree, cleanupTreeID != ObjectIdentifier(tree) else { return }
        loadCleanupSuggestions()
    }

    public func loadCleanupSuggestions() {
        guard let tree else {
            resetCleanup()
            return
        }
        cleanupGeneration += 1
        let generation = cleanupGeneration
        cleanupTreeID = ObjectIdentifier(tree)
        cleanupLoading = true

        let environment = CleanupEnvironment(
            homePath: homePath,
            runningBundleIdentifiers: runningBundleIdentifiers()
        )
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let suggestions = CleanupAdvisor.recommend(tree: tree, environment: environment)
            let months = UserDefaults.standard.object(forKey: AppSettingsKeys.staleMonths) as? Int ?? 12
            let stale = StaleFiles.find(
                tree: tree,
                options: StaleOptions(months: months, now: Date())
            )
            let staleSuggestions = stale.files.map { file in
                CleanupSuggestion(
                    id: "stale:\(file.index)",
                    ruleID: "stale",
                    title: "Заброшенные файлы",
                    nodeIndex: file.index,
                    name: file.name,
                    path: file.path,
                    relativePath: file.relativePath,
                    size: file.size,
                    itemCount: 1,
                    risk: .review,
                    reason: L10n.isEnglish
                        ? "Not modified for \(file.ageDays) days"
                        : "Не изменялся \(file.ageDays) дн.",
                    isDirectory: false,
                    disposition: .trash,
                    isSelectedByDefault: false
                )
            }
            let all = suggestions + staleSuggestions
            DispatchQueue.main.async {
                guard let self,
                      self.cleanupGeneration == generation,
                      let current = self.tree,
                      current === tree else { return }
                self.cleanupSuggestions = all
                self.staleResult = stale
                self.cleanupSelection = Set(
                    suggestions.filter { $0.isSelectedByDefault }.map(\.id)
                )
                self.cleanupLoading = false
            }
        }
    }
}
