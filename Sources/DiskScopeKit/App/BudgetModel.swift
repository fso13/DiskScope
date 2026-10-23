import Combine
import Foundation

/// Owns folder limits, their evaluation and one-time notifications.
@MainActor
public final class BudgetModel: ObservableObject {
    @Published public internal(set) var budgets: [FolderBudget] = FolderBudgetStore.load()

    private var treeProvider: () -> ScanTree? = { nil }
    private var historyProvider: () -> [ScanHistoryEntry] = { [] }
    private var observer: NSObjectProtocol?

    public init() {
        observer = NotificationCenter.default.addObserver(
            forName: .folderBudgetsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.budgets = FolderBudgetStore.load()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func attach(
        treeProvider: @escaping () -> ScanTree?,
        historyProvider: @escaping () -> [ScanHistoryEntry]
    ) {
        self.treeProvider = treeProvider
        self.historyProvider = historyProvider
    }

    public func set(path: String, limitBytes: Int64) {
        budgets = FolderBudgetStore.upsert(path: path, limitBytes: limitBytes)
    }

    public func remove(path: String) {
        budgets = FolderBudgetStore.remove(path: path)
    }

    public func budget(forPath path: String) -> FolderBudget? {
        FolderBudgetEvaluator.matching(path: path, in: budgets)
    }

    public func status(forPath path: String) -> FolderBudgetStatus? {
        guard let tree = treeProvider(),
              let index = tree.index(ofPath: path),
              let budget = budget(forPath: path) else { return nil }
        return FolderBudgetStatus(budget: budget, currentBytes: tree.node(index).size)
    }

    public func status(forNode index: Int32) -> FolderBudgetStatus? {
        guard let tree = treeProvider(), index >= 0, Int(index) < tree.count else { return nil }
        return status(forPath: tree.path(of: index))
    }

    /// Top-level folder growth compared with the previous scan of the same root.
    public func delta(forPath path: String) -> Int64? {
        guard let tree = treeProvider() else { return nil }
        let relative = String(path.dropFirst(tree.rootPath == "/" ? 1 : tree.rootPath.count + 1))
        guard !relative.isEmpty, !relative.contains("/") else { return nil }
        guard let previous = historyProvider().dropFirst().first(where: { $0.rootPath == tree.rootPath }),
              let before = previous.folderSizes[relative],
              let index = tree.index(ofPath: path) else { return nil }
        return tree.node(index).size - before
    }

    func notifyExceeded(tree: ScanTree, onExceeded: (FolderBudgetStatus) -> Void) {
        let statuses = budgets.compactMap { budget -> FolderBudgetStatus? in
            guard let index = tree.index(ofPath: budget.path) else { return nil }
            return FolderBudgetStatus(budget: budget, currentBytes: tree.node(index).size)
        }
        for status in FolderBudgetNotifier.newlyExceeded(statuses) {
            onExceeded(status)
        }
    }
}
