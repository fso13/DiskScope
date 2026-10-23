import AppKit
import Combine
import Foundation

/// Owns destructive trash operations and their undo flow.
@MainActor
public final class TrashOperationsModel: ObservableObject {
    weak var appModel: AppModel?

    public init() {}

    func attach(appModel: AppModel) {
        self.appModel = appModel
    }

    // MARK: - Availability

    public var canTrashSelection: Bool {
        guard let model = appModel, let tree = model.tree, !model.selection.isEmpty else {
            return false
        }
        return model.selection.allSatisfy { index in
            index > 0 && !tree.isDeleted(index) && tree.node(index).nodeKind != .aggregate
        }
    }

    public var canTrashCollection: Bool {
        guard let model = appModel else { return false }
        return !model.collection.isEmpty && !model.fileOperationInFlight
    }

    // MARK: - Selection

    public func requestSelection() {
        guard canTrashSelection else { return }
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.confirmTrash) {
            appModel?.trash.showSelectionConfirmation = true
        } else {
            confirmSelection()
        }
    }

    public func confirmSelection() {
        guard let model = appModel else { return }
        model.trash.showSelectionConfirmation = false
        guard canTrashSelection, let tree = model.tree else { return }
        perform(indices: topLevelSelection(), tree: tree)
    }

    // MARK: - Collection

    public func requestCollection() {
        guard canTrashCollection, let model = appModel else { return }
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.confirmTrash) {
            model.trash.showCollectionConfirmation = true
        } else {
            confirmCollection()
        }
    }

    public func confirmCollection() {
        guard let model = appModel else { return }
        model.trash.showCollectionConfirmation = false
        model.showCollection = false
        guard canTrashCollection, let tree = model.tree else { return }
        perform(indices: model.collection.sorted(), tree: tree)
    }

    // MARK: - Trash

    private func perform(indices: [Int32], tree: ScanTree) {
        guard let model = appModel, !model.fileOperationInFlight, !indices.isEmpty else { return }
        let urls = indices.map { tree.url(of: $0) }
        model.selection = []
        model.fileOperationInFlight = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var trashed: [(index: Int32, original: URL, trashed: URL)] = []
            var failures: [(url: URL, message: String)] = []
            for (offset, url) in urls.enumerated() {
                do {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                    let trashedURL = (resultingURL as URL?) ?? url
                    trashed.append((indices[offset], url, trashedURL))
                } catch {
                    failures.append((url, error.localizedDescription))
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(tree: tree, trashed: trashed, failures: failures)
            }
        }
    }

    private func apply(
        tree scanTree: ScanTree,
        trashed: [(index: Int32, original: URL, trashed: URL)],
        failures: [(url: URL, message: String)]
    ) {
        guard let model = appModel else { return }
        model.fileOperationInFlight = false
        guard !trashed.isEmpty else {
            if let failure = failures.first {
                model.errorMessage = "Не удалось переместить «\(failure.url.lastPathComponent)» в Корзину: \(failure.message)"
            }
            return
        }
        let removed = scanTree.removingSubtrees(at: trashed.map(\.index))
        record(removal: removed, trashed: trashed, model: model)
        model.collection = model.collection.filter { !removed.tree.isDeleted($0) }
        model.resetDuplicates()
        model.resetSimilar()
        model.fileCount = removed.tree.totalFiles
        model.folderCount = removed.tree.directoryCount()
        model.tree = removed.tree
        model.selection = []
        // A package containing the current folder could be removed from the
        // "largest" list; fall back to the nearest surviving ancestor.
        if removed.tree.isDeleted(model.currentIndex) {
            var cursor = model.currentIndex
            while cursor > 0, removed.tree.isDeleted(cursor) {
                cursor = removed.tree.node(cursor).parent
            }
            model.currentIndex = max(cursor, 0)
        }
        model.rebuildCurrentRows()
        model.browser.refreshVolumes()
        model.stats.refresh()
        model.invalidateCleanup()
        model.showToast(
            "В Корзину: \(Plural.items(trashed.count)) · \(ByteFormat.string(removed.bytes)) · ⌘Z — отменить",
            symbol: "trash.fill"
        )
        if let failure = failures.first {
            model.errorMessage = "Часть объектов не удалось удалить. «\(failure.url.lastPathComponent)»: \(failure.message)"
        }
    }

    /// Moves the files of the last deletion back and restores their subtrees.
    public func undoLast() {
        guard let model = appModel, !model.fileOperationInFlight, let entry = model.trash.popUndo() else {
            return
        }
        model.fileOperationInFlight = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var restoredGroups: [ScanTreeRemoval.Group] = []
            var failures: [(url: URL, message: String)] = []
            var restoredCount = 0
            for file in entry.files {
                let manager = FileManager.default
                guard manager.fileExists(atPath: file.trashedURL.path) else {
                    failures.append((file.originalURL, "файл не найден в Корзине"))
                    continue
                }
                guard !manager.fileExists(atPath: file.originalURL.path) else {
                    failures.append((file.originalURL, "путь уже занят другим файлом"))
                    continue
                }
                do {
                    try manager.moveItem(at: file.trashedURL, to: file.originalURL)
                    restoredGroups.append(file.group)
                    restoredCount += 1
                } catch {
                    failures.append((file.originalURL, error.localizedDescription))
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let restoredRoots = Set(restoredGroups.map(\.root))
                self.applyUndo(
                    groups: restoredGroups,
                    collectionRoots: entry.collectionRoots.filter { restoredRoots.contains($0) },
                    restoredCount: restoredCount,
                    failures: failures
                )
            }
        }
    }

    private func applyUndo(
        groups: [ScanTreeRemoval.Group],
        collectionRoots: [Int32],
        restoredCount: Int,
        failures: [(url: URL, message: String)]
    ) {
        guard let model = appModel else { return }
        model.fileOperationInFlight = false
        if !groups.isEmpty, let tree = model.tree {
            let restored = tree.restoringSubtrees(groups: groups)
            model.tree = restored
            model.resetDuplicates()
            model.resetSimilar()
            model.addToCollection(collectionRoots)
            model.selection = []
            model.fileCount = restored.totalFiles
            model.folderCount = restored.directoryCount()
            if restored.isDeleted(model.currentIndex) {
                var cursor = model.currentIndex
                while cursor > 0, restored.isDeleted(cursor) {
                    cursor = restored.node(cursor).parent
                }
                model.currentIndex = max(cursor, 0)
            }
            model.rebuildCurrentRows()
            model.browser.refreshVolumes()
            model.stats.refresh()
            model.invalidateCleanup()
            let bytes = groups.reduce(Int64(0)) { $0 + $1.bytes }
            model.showToast(
                "Возвращено: \(Plural.items(restoredCount)) · \(ByteFormat.string(bytes))",
                symbol: "arrow.uturn.backward"
            )
        }
        if let failure = failures.first {
            model.errorMessage = "Не удалось вернуть «\(failure.url.lastPathComponent)»: \(failure.message)"
        }
    }

    private func record(
        removal: ScanTreeRemoval,
        trashed: [(index: Int32, original: URL, trashed: URL)],
        model: AppModel
    ) {
        let roots = Array(Set(trashed.map(\.index)))
        model.trash.record(
            removal: removal,
            trashed: trashed,
            collectionRoots: roots.filter { model.collection.contains($0) }
        )
    }

    private func topLevelSelection() -> [Int32] {
        guard let model = appModel, let tree = model.tree else { return [] }
        var result: [Int32] = []
        for index in model.selection.sorted() {
            guard index > 0, Int(index) < tree.count, !tree.isDeleted(index) else { continue }
            var ancestor = tree.node(index).parent
            var hasSelectedAncestor = false
            while ancestor >= 0 {
                if model.selection.contains(ancestor) {
                    hasSelectedAncestor = true
                    break
                }
                ancestor = tree.node(ancestor).parent
            }
            if !hasSelectedAncestor { result.append(index) }
        }
        return result
    }
}
