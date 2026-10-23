import Combine
import Foundation

/// Owns the largest-items list and category stats derived from the current tree.
@MainActor
public final class DerivedStatsModel: ObservableObject {
    @Published public internal(set) var largestItems: [AppModel.ItemRow] = []
    @Published public internal(set) var categoryStats: [CategoryStat] = []

    private var treeProvider: () -> ScanTree? = { nil }
    private var categoryProvider: () -> FileCategory? = { nil }
    private var searchProvider: () -> String = { "" }
    private var generation = 0

    public init() {}

    func attach(
        treeProvider: @escaping () -> ScanTree?,
        categoryProvider: @escaping () -> FileCategory?,
        searchProvider: @escaping () -> String
    ) {
        self.treeProvider = treeProvider
        self.categoryProvider = categoryProvider
        self.searchProvider = searchProvider
    }

    public var filteredLargestRows: [AppModel.ItemRow] {
        var rows = largestItems
        if let filter = categoryProvider() {
            rows = rows.filter { $0.category == filter }
        }
        let query = searchProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.relativePath.localizedCaseInsensitiveContains(query)
            }
        }
        return rows
    }

    public func refresh() {
        guard let tree = treeProvider() else { return }
        generation += 1
        let generation = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = tree.largestItems(limit: 4000)
            let rows = items.map { index in
                ItemRowFactory.make(tree: tree, index: index, parentSize: max(tree.totalSize, 1), includePaths: true)
            }
            let stats = tree.categoryStats()
            DispatchQueue.main.async {
                guard let self, self.generation == generation, self.treeProvider() === tree else { return }
                self.largestItems = rows
                self.categoryStats = stats
            }
        }
    }

    /// Fills derived state synchronously; used by previews and snapshots.
    func apply(tree: ScanTree) {
        generation += 1
        largestItems = tree.largestItems(limit: 4000).map { index in
            ItemRowFactory.make(tree: tree, index: index, parentSize: max(tree.totalSize, 1), includePaths: true)
        }
        categoryStats = tree.categoryStats()
    }

    func reset() {
        generation += 1
        largestItems = []
        categoryStats = []
    }
}
