import Combine
import Foundation

/// Fills app state for snapshots and previews without running real scans.
@MainActor
public final class PreviewModel: ObservableObject {
    weak var appModel: AppModel?

    public init() {}

    func attach(appModel: AppModel) {
        self.appModel = appModel
    }

    /// Loads a fully scanned tree as preview state.
    public func load(tree: ScanTree) {
        guard let model = appModel else { return }
        model.scan.invalidate()
        model.scan.finish(tree)
        model.currentIndex = 0
        model.tab = .map
        model.selection = []
        model.resetTrashUndo()
        model.resetCleanup()
        model.resetCollection()
        model.search.reset()
        model.resetDuplicates()
        model.resetSimilar()
        model.fileCount = tree.totalFiles
        model.folderCount = tree.directoryCount()
        model.volumes = VolumeInfo.loadAll()
        model.rebuildCurrentRows()
        model.largestItems = tree.largestItems(limit: 4000).map {
            ItemRowFactory.make(tree: tree, index: $0, parentSize: max(tree.totalSize, 1), includePaths: true)
        }
        model.categoryStats = tree.categoryStats()
    }

    /// Fills cleanup state without running the advisor; used by snapshots.
    public func cleanup(_ suggestions: [CleanupSuggestion]) {
        appModel?.cleanup.preview(suggestions)
    }

    /// Fills similar-image groups without running Vision; used by snapshots.
    public func similar(_ groups: [SimilarImageGroup]) {
        appModel?.similar.preview(groups)
    }

    /// Fills duplicate groups without hashing files; used by snapshots.
    public func duplicates(_ groups: [DuplicateGroup]) {
        appModel?.duplicates.preview(groups)
    }

    /// Fills disk overview state without scanning the real Trash; used by snapshots.
    public func diskOverview(_ overview: DiskOverview) {
        appModel?.disk.preview(overview)
    }

    public func scanning(path: String, progress: ScanProgress) {
        guard let model = appModel else { return }
        model.scan.previewScanning(path: path, progress: progress)
        model.currentIndex = 0
        model.resetTrashUndo()
        model.resetCleanup()
        model.resetCollection()
        model.search.reset()
        model.resetDuplicates()
        model.resetSimilar()
        model.volumes = VolumeInfo.loadAll()
    }

    public func welcome() {
        guard let model = appModel else { return }
        model.scan.previewWelcome()
        model.currentIndex = 0
        model.resetTrashUndo()
        model.resetCleanup()
        model.resetCollection()
        model.search.reset()
        model.resetDuplicates()
        model.resetSimilar()
        model.volumes = VolumeInfo.loadAll()
    }

    public func select(index: Int32) {
        appModel?.selection = [index]
    }

    public func navigate(to index: Int32) {
        appModel?.navigate(to: index)
    }
}
