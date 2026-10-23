import Combine
import Foundation

/// Owns cleanup recommendations, stale files and the selection.
@MainActor
public final class CleanupModel: ObservableObject {
    @Published public internal(set) var suggestions: [CleanupSuggestion] = []
    @Published public internal(set) var staleResult: StaleResult = .empty
    @Published public var selection: Set<String> = []
    @Published public internal(set) var loading = false
    @Published public var showConfirmation = false

    private var treeProvider: () -> ScanTree? = { nil }
    private var environmentProvider: () -> CleanupEnvironment = { .current() }
    private var busyProvider: () -> Bool = { false }
    private var generation = 0
    private var loadedTreeID: ObjectIdentifier?

    public init() {}

    func attach(
        treeProvider: @escaping () -> ScanTree?,
        environmentProvider: @escaping () -> CleanupEnvironment,
        busyProvider: @escaping () -> Bool
    ) {
        self.treeProvider = treeProvider
        self.environmentProvider = environmentProvider
        self.busyProvider = busyProvider
    }

    public var staleSuggestions: [CleanupSuggestion] {
        suggestions.filter { $0.ruleID == "stale" }
    }

    public var selectedSuggestions: [CleanupSuggestion] {
        suggestions.filter { selection.contains($0.id) }
    }

    public var selectedSize: Int64 {
        selectedSuggestions.reduce(Int64(0)) { $0 + $1.size }
    }

    public var selectedCount: Int { selectedSuggestions.count }

    public var totalSize: Int64 {
        suggestions.filter { $0.ruleID != "stale" }.reduce(Int64(0)) { $0 + $1.size }
            + staleResult.totalBytes
    }

    public var canApply: Bool {
        !selection.isEmpty && !loading && !busyProvider()
    }

    public var hasPermanentSelection: Bool {
        selectedSuggestions.contains { $0.disposition == .deletePermanently }
    }

    public var confirmationMessage: String {
        let size = ByteFormat.string(selectedSize)
        if hasPermanentSelection {
            return "\(Plural.items(selectedCount)) · \(size). Среди них есть объекты, которые удаляются безвозвратно; отменить это через ⌘Z не получится."
        }
        return "\(Plural.items(selectedCount)) · \(size). Файлы можно вернуть из Корзины через ⌘Z."
    }

    public func loadIfNeeded() {
        guard let tree = treeProvider(), loadedTreeID != ObjectIdentifier(tree) else { return }
        load()
    }

    public func load() {
        guard let tree = treeProvider() else {
            reset()
            return
        }
        generation += 1
        let generation = generation
        loadedTreeID = ObjectIdentifier(tree)
        loading = true

        let environment = environmentProvider()
        let months = UserDefaults.standard.object(forKey: AppSettingsKeys.staleMonths) as? Int ?? 12
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let suggestions = CleanupAdvisor.recommend(tree: tree, environment: environment)
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
            DispatchQueue.main.async {
                guard let self,
                      self.generation == generation,
                      self.treeProvider() === tree else { return }
                self.suggestions = suggestions + staleSuggestions
                self.staleResult = stale
                self.selection = Set(
                    suggestions.filter { $0.isSelectedByDefault }.map(\.id)
                )
                self.loading = false
            }
        }
    }

    public func reset() {
        generation += 1
        suggestions = []
        staleResult = .empty
        selection = []
        loading = false
        loadedTreeID = nil
        showConfirmation = false
    }

    func preview(_ items: [CleanupSuggestion]) {
        reset()
        suggestions = items
        selection = Set(items.filter { $0.isSelectedByDefault }.map(\.id))
        loadedTreeID = treeProvider().map { ObjectIdentifier($0) }
    }

    public func toggle(_ id: String) {
        if !selection.insert(id).inserted {
            selection.remove(id)
        }
    }

    public func select(_ items: [CleanupSuggestion]) {
        for item in items { selection.insert(item.id) }
    }

    public func selectDefaults() {
        for suggestion in suggestions where suggestion.isSelectedByDefault {
            selection.insert(suggestion.id)
        }
    }

    public func clearSelection() {
        selection = []
    }
}
