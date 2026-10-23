import Foundation

extension AppModel {
    public func setFolderBudget(path: String, limitBytes: Int64) {
        folderBudgets = FolderBudgetStore.upsert(path: path, limitBytes: limitBytes)
    }

    public func removeFolderBudget(path: String) {
        folderBudgets = FolderBudgetStore.remove(path: path)
    }

    public func folderBudget(forPath path: String) -> FolderBudget? {
        FolderBudgetEvaluator.matching(path: path, in: folderBudgets)
    }

    public func folderBudgetStatus(forPath path: String) -> FolderBudgetStatus? {
        guard let tree,
              let index = tree.index(ofPath: path),
              let budget = folderBudget(forPath: path) else { return nil }
        return FolderBudgetStatus(budget: budget, currentBytes: tree.node(index).size)
    }

    public func folderBudgetStatus(forNode index: Int32) -> FolderBudgetStatus? {
        guard let tree, index >= 0, Int(index) < tree.count else { return nil }
        return folderBudgetStatus(forPath: tree.path(of: index))
    }

    /// Top-level folder growth compared with the previous scan of the same root.
    public func folderBudgetDelta(forPath path: String) -> Int64? {
        guard let tree else { return nil }
        let relative = String(path.dropFirst(tree.rootPath == "/" ? 1 : tree.rootPath.count + 1))
        guard !relative.isEmpty, !relative.contains("/") else { return nil }
        guard let previous = scanHistory.dropFirst().first(where: { $0.rootPath == tree.rootPath }),
              let before = previous.folderSizes[relative] else { return nil }
        guard let index = tree.index(ofPath: path) else { return nil }
        return tree.node(index).size - before
    }

    func notifyExceededBudgets(_ tree: ScanTree) {
        let statuses = folderBudgets.compactMap { budget -> FolderBudgetStatus? in
            guard let index = tree.index(ofPath: budget.path) else { return nil }
            return FolderBudgetStatus(budget: budget, currentBytes: tree.node(index).size)
        }
        let exceeded = FolderBudgetNotifier.newlyExceeded(statuses)
        for status in exceeded {
            showToast(
                "Лимит превышен: \(URL(fileURLWithPath: status.budget.path).lastPathComponent) +"
                    + ByteFormat.string(status.overBy),
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }
}
