import AppKit
import Combine
import Foundation

/// Owns cleanup confirmation and destructive cleanup operations.
@MainActor
public final class CleanupOperationsModel: ObservableObject {
    weak var appModel: AppModel?

    public init() {}

    func attach(appModel: AppModel) {
        self.appModel = appModel
    }

    public func request() {
        guard let model = appModel, model.cleanup.canApply else { return }
        if model.cleanup.hasPermanentSelection
            || UserDefaults.standard.bool(forKey: AppSettingsKeys.confirmTrash) {
            model.cleanup.showConfirmation = true
        } else {
            confirm()
        }
    }

    public func confirm() {
        guard let model = appModel else { return }
        model.cleanup.showConfirmation = false
        guard !model.fileOperationInFlight, !model.isScanning, let tree = model.tree else { return }
        let selected = model.cleanup.selectedSuggestions.filter { suggestion in
            suggestion.nodeIndex > 0
                && Int(suggestion.nodeIndex) < tree.count
                && !tree.isDeleted(suggestion.nodeIndex)
        }
        guard !selected.isEmpty else { return }
        model.fileOperationInFlight = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var trashed: [(index: Int32, original: URL, trashed: URL)] = []
            var permanent: [Int32] = []
            var failures: [(url: URL, message: String)] = []
            for suggestion in selected {
                let url = URL(fileURLWithPath: suggestion.path)
                do {
                    if suggestion.disposition == .deletePermanently {
                        try FileManager.default.removeItem(at: url)
                        permanent.append(suggestion.nodeIndex)
                    } else {
                        var resultingURL: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                        trashed.append((suggestion.nodeIndex, url, (resultingURL as URL?) ?? url))
                    }
                } catch {
                    failures.append((url, error.localizedDescription))
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(
                    tree: tree,
                    trashed: trashed,
                    permanent: permanent,
                    failures: failures
                )
            }
        }
    }

    private func apply(
        tree scanTree: ScanTree,
        trashed: [(index: Int32, original: URL, trashed: URL)],
        permanent: [Int32],
        failures: [(url: URL, message: String)]
    ) {
        guard let model = appModel else { return }
        model.fileOperationInFlight = false
        let indices = trashed.map(\.index) + permanent
        guard !indices.isEmpty else {
            if let failure = failures.first {
                model.errorMessage = "Не удалось очистить «\(failure.url.lastPathComponent)»: \(failure.message)"
            }
            return
        }

        let removed = scanTree.removingSubtrees(at: indices)
        let roots = Array(Set(trashed.map(\.index)))
        model.trash.record(
            removal: removed,
            trashed: trashed,
            collectionRoots: roots.filter { model.collection.contains($0) }
        )
        model.collection = model.collection.filter { !removed.tree.isDeleted($0) }
        model.resetDuplicates()
        model.resetSimilar()
        model.fileCount = removed.tree.totalFiles
        model.folderCount = removed.tree.directoryCount()
        model.tree = removed.tree
        model.selection = []
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

        var text = "Очищено: \(Plural.items(indices.count)) · \(ByteFormat.string(removed.bytes))"
        if !permanent.isEmpty {
            text += " · безвозвратно: \(Plural.items(permanent.count))"
        }
        model.showToast(text, symbol: "sparkles")
        if let failure = failures.first {
            model.errorMessage = "Не удалось очистить «\(failure.url.lastPathComponent)»: \(failure.message)"
        }
    }
}
