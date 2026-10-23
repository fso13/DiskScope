import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class AppModel: ObservableObject {
    public enum Phase: Equatable {
        case welcome
        case scanning
        case ready
        case failed(String)
    }

    public enum Tab: String, CaseIterable, Identifiable {
        case map
        case largest
        case types
        case media
        case cleanup
        case disk
        case duplicates
        case similar

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .map: return "Карта"
            case .largest: return "Крупнейшие"
            case .types: return "Типы файлов"
            case .media: return "Медиа"
            case .cleanup: return "Очистка"
            case .disk: return "Диск"
            case .duplicates: return "Дубликаты"
            case .similar: return "Похожие"
            }
        }

        public var symbol: String {
            switch self {
            case .map: return "square.grid.2x2"
            case .largest: return "list.number"
            case .types: return "chart.bar.xaxis"
            case .media: return "photo.on.rectangle.angled"
            case .cleanup: return "sparkles"
            case .disk: return "internaldrive"
            case .duplicates: return "doc.on.doc"
            case .similar: return "photo.stack"
            }
        }
    }

    public struct ItemRow: Identifiable, Hashable, Sendable {
        public let id: Int32
        public let name: String
        public let path: String
        public let relativePath: String
        public let size: Int64
        public let category: FileCategory
        public let isContainer: Bool
        public let isAggregate: Bool
        public let isHardLink: Bool
        public let itemCount: Int
        public let fraction: Double
        public let depth: Int

        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: ItemRow, rhs: ItemRow) -> Bool { lhs.id == rhs.id }
    }

    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public let text: String
        public let symbol: String
    }

    @Published public internal(set) var scan = ScanController()
    @Published public private(set) var currentIndex: Int32 = 0
    @Published public var tab: Tab = .map {
        didSet {
            if tab == .cleanup {
                loadCleanupSuggestionsIfNeeded()
            }
        }
    }
    @Published public var selection: Set<Int32> = []

    @Published public private(set) var volumes: [VolumeInfo] = VolumeInfo.loadAll()
    @Published public private(set) var fileCount = 0
    @Published public private(set) var folderCount = 0
    @Published public private(set) var largestItems: [ItemRow] = []
    @Published public private(set) var categoryStats: [CategoryStat] = []
    @Published public private(set) var media = MediaModel()
    @Published public private(set) var currentRows: [ItemRow] = []
    @Published public private(set) var currentRowsTotal = 0
    @Published public private(set) var currentRowsTruncated = false
    @Published public var searchText = "" { didSet { rebuildCurrentRows() } }
    @Published public var sortOrder: [KeyPathComparator<ItemRow>] = [KeyPathComparator(\.size, order: .reverse)] {
        didSet { rebuildCurrentRows() }
    }
    @Published public var categoryFilter: FileCategory?
    @Published public var toast: Toast?
    @Published public var errorMessage: String?
    @Published public var showCommandPalette = false
    @Published public var showPermissionSheet = false
    @Published public internal(set) var trash = TrashModel()
    @Published public internal(set) var cleanup = CleanupModel()
    @Published public internal(set) var collection: Set<Int32> = []
    @Published public var showCollection = false
    @Published public internal(set) var search = SearchModel()
    @Published public internal(set) var disk = DiskModel()
    @Published public internal(set) var history = HistoryModel()
    @Published public internal(set) var duplicates = DuplicatesModel()
    @Published public var similarOptions = SimilarImageOptions() {
        didSet { resetSimilar() }
    }
    @Published public internal(set) var similarState = SimilarImageState()
    @Published public var showInspector = false
    @Published public var quickLookURL: URL?

    @Published public internal(set) var budget = BudgetModel()

    var similarCancellation: ScanCancellation?
    private var toastWorkItem: DispatchWorkItem?
    private var derivedGeneration = 0
    private let rowLimit = 2500
    private var cleanupCancellable: AnyCancellable?
    private var diskCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var searchCancellable: AnyCancellable?

    public init() {
        UserDefaults.standard.register(defaults: [
            AppSettingsKeys.appearance: AppAppearance.system.rawValue,
            AppSettingsKeys.confirmTrash: true,
            AppSettingsKeys.language: AppLanguage.system.rawValue,
            AppSettingsKeys.menuBarMonitor: false,
            AppSettingsKeys.menuBarDisplay: MenuBarDisplayMode.free.rawValue,
            AppSettingsKeys.parallelTraversal: true,
            AppSettingsKeys.staleMonths: 12,
        ])
        search.attach { [weak self] in self?.tree }
        searchCancellable = search.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        cleanup.attach(
            treeProvider: { [weak self] in self?.tree },
            environmentProvider: { [weak self] in
                guard let self else { return .current() }
                return CleanupEnvironment(
                    homePath: self.homePath,
                    runningBundleIdentifiers: self.runningBundleIdentifiers()
                )
            },
            busyProvider: { [weak self] in self?.fileOperationInFlight ?? false }
        )
        cleanupCancellable = cleanup.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        scan.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        duplicates.attach { [weak self] in self?.tree }
        duplicates.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        trash.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        disk.attach { [weak self] in self?.internalVolume }
        diskCancellable = disk.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        history.attach { [weak self] in self?.tree }
        history.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        budget.attach(
            treeProvider: { [weak self] in self?.tree },
            historyProvider: { [weak self] in self?.history.entries ?? [] }
        )
        budget.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        media.attach(appModel: self)
    }

    // MARK: - Scan compatibility

    public var phase: Phase {
        get { scan.phase }
        set { scan.phase = newValue }
    }

    public var tree: ScanTree? {
        get { scan.tree }
        set { scan.tree = newValue }
    }

    public var progress: ScanProgress? {
        get { scan.progress }
        set { scan.progress = newValue }
    }

    public var lastScanPath: String? { scan.lastScanPath }

    var fileOperationInFlight: Bool {
        get { trash.busy }
        set { trash.busy = newValue }
    }

    public var canUndoTrash: Bool { trash.canUndo }
    public var showTrashConfirmation: Bool {
        get { trash.showSelectionConfirmation }
        set { trash.showSelectionConfirmation = newValue }
    }
    public var showCollectionTrashConfirmation: Bool {
        get { trash.showCollectionConfirmation }
        set { trash.showCollectionConfirmation = newValue }
    }

    // MARK: - Derived state

    public var filteredLargestRows: [ItemRow] {
        var rows = largestItems
        if let filter = categoryFilter {
            rows = rows.filter { $0.category == filter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.relativePath.localizedCaseInsensitiveContains(query)
            }
        }
        return rows
    }

    public var scanSummary: String {
        guard let tree else { return "" }
        return "\(ByteFormat.string(tree.totalSize)) · \(Plural.files(tree.totalFiles)) · \(Plural.folders(folderCount))"
    }

    // MARK: - Scanning

    public func scan(path: String) {
        guard !isScanning, !fileOperationInFlight else { return }

        let standardized: String
        if path == "/" {
            standardized = "/"
        } else {
            standardized = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        }

        selection = []
        categoryFilter = nil
        searchText = ""
        resetTrashUndo()
        resetCleanup()
        resetCollection()
        search.reset()
        resetDuplicates()
        resetSimilar()

        let cacheDirectory = ScanTreeCache.defaultURL.deletingLastPathComponent().path
        let parallel = UserDefaults.standard.object(forKey: AppSettingsKeys.parallelTraversal) as? Bool ?? true
        let options = ScanOptions(excludedPaths: [cacheDirectory], parallelTraversal: parallel)
        scan.start(
            path: standardized,
            options: options,
            onResult: { [weak self] result, cached in
                guard let self else { return }
                self.finishScan(result)
                if cached {
                    self.showToast("Кэш дерева: изменений нет", symbol: "bolt.horizontal.circle")
                }
            },
            onFailure: { [weak self] error, cancelled in
                self?.failScan(error, wasCancelled: cancelled)
            }
        )
    }

    public func rescan() {
        if let tree {
            scan(path: tree.rootPath)
        } else if let lastScanPath {
            scan(path: lastScanPath)
        } else {
            scan(path: homePath)
        }
    }

    public func cancelScan() {
        scan.cancel()
        if tab == .cleanup {
            loadCleanupSuggestionsIfNeeded()
        }
    }

    private func finishScan(_ result: ScanTree) {
        scan.finish(result)
        currentIndex = 0
        selection = []
        tab = .map
        fileCount = result.totalFiles
        folderCount = result.directoryCount()
        refreshVolumes()
        rebuildCurrentRows()
        refreshDerived()
        history.record(result)
        notifyExceededBudgets(result)
    }

    private func failScan(_ error: Error, wasCancelled: Bool) {
        progress = nil
        if wasCancelled {
            phase = tree == nil ? .welcome : .ready
            return
        }
        scan.fail(error)
        errorMessage = error.localizedDescription
    }

    private func refreshDerived() {
        guard let tree else { return }
        derivedGeneration += 1
        let generation = derivedGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = tree.largestItems(limit: 4000)
            let rows = items.map { index in
                ItemRowFactory.make(tree: tree, index: index, parentSize: max(tree.totalSize, 1), includePaths: true)
            }
            let stats = tree.categoryStats()
            DispatchQueue.main.async {
                guard let self, self.derivedGeneration == generation, self.tree === tree else { return }
                self.largestItems = rows
                self.categoryStats = stats
            }
        }
    }

    // MARK: - Navigation

    public func navigate(to index: Int32) {
        guard let tree, index >= 0, Int(index) < tree.count, !tree.isDeleted(index) else { return }
        guard tree.node(index).nodeKind.isContainer else { return }
        currentIndex = index
        selection = []
        searchText = ""
        rebuildCurrentRows()
    }

    public func goUp() {
        guard let tree else { return }
        let parent = tree.node(currentIndex).parent
        if parent >= 0 { navigate(to: parent) }
    }

    public func goToRoot() {
        navigate(to: 0)
    }

    /// Double-click / Enter behaviour: folders open, everything else is revealed in Finder.
    public func activateRow(_ index: Int32) {
        guard let tree, index >= 0, Int(index) < tree.count else { return }
        guard tree.node(index).nodeKind != .aggregate else { return }
        if tree.node(index).nodeKind == .directory {
            navigate(to: index)
        } else {
            reveal(indices: [index])
        }
    }

    public func openRow(_ index: Int32) {
        guard let tree, index >= 0, Int(index) < tree.count else { return }
        let node = tree.node(index)
        guard node.nodeKind != .aggregate else { return }
        if node.nodeKind.isContainer {
            navigate(to: index)
        } else {
            let url = tree.url(of: index)
            if !NSWorkspace.shared.open(url) {
                errorMessage = "Не удалось открыть «\(tree.name(of: index))»"
            }
        }
    }

    public func reveal(indices: [Int32]) {
        guard let tree else { return }
        let urls = indices.compactMap { index -> URL? in
            guard index >= 0, Int(index) < tree.count, !tree.isDeleted(index) else { return nil }
            return tree.url(of: index)
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    public func revealSelection() {
        reveal(indices: Array(selection))
    }

    public func revealCurrentFolder() {
        guard let tree else { return }
        NSWorkspace.shared.activateFileViewerSelecting([tree.url(of: currentIndex)])
    }

    // MARK: - Trash

    public func requestTrashSelection() {
        guard canTrashSelection else { return }
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.confirmTrash) {
            showTrashConfirmation = true
        } else {
            confirmTrash()
        }
    }

    public func confirmTrash() {
        showTrashConfirmation = false
        guard let tree, canTrashSelection else { return }
        performTrash(indices: topLevelSelection(), tree: tree)
    }

    public func confirmCollectionTrash() {
        showCollectionTrashConfirmation = false
        showCollection = false
        guard let tree, canTrashCollection else { return }
        performTrash(indices: collection.sorted(), tree: tree)
    }

    private func performTrash(indices: [Int32], tree: ScanTree) {
        guard !fileOperationInFlight, !indices.isEmpty else { return }
        let urls = indices.map { tree.url(of: $0) }
        selection = []
        fileOperationInFlight = true

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
                self.applyTrash(tree: tree, trashed: trashed, failures: failures)
            }
        }
    }

    private func applyTrash(
        tree scanTree: ScanTree,
        trashed: [(index: Int32, original: URL, trashed: URL)],
        failures: [(url: URL, message: String)]
    ) {
        fileOperationInFlight = false
        guard !trashed.isEmpty else {
            if let failure = failures.first {
                errorMessage = "Не удалось переместить «\(failure.url.lastPathComponent)» в Корзину: \(failure.message)"
            }
            return
        }
        let removed = scanTree.removingSubtrees(at: trashed.map(\.index))
        recordUndo(removal: removed, trashed: trashed)
        collection = collection.filter { !removed.tree.isDeleted($0) }
        resetDuplicates()
        resetSimilar()
        fileCount = removed.tree.totalFiles
        folderCount = removed.tree.directoryCount()
        tree = removed.tree
        selection = []
        // A package containing the current folder could be removed from the
        // "largest" list; fall back to the nearest surviving ancestor.
        if removed.tree.isDeleted(currentIndex) {
            var cursor = currentIndex
            while cursor > 0, removed.tree.isDeleted(cursor) {
                cursor = removed.tree.node(cursor).parent
            }
            currentIndex = max(cursor, 0)
        }
        rebuildCurrentRows()
        refreshVolumes()
        refreshDerived()
        invalidateCleanup()
        showToast(
            "В Корзину: \(Plural.items(trashed.count)) · \(ByteFormat.string(removed.bytes)) · ⌘Z — отменить",
            symbol: "trash.fill"
        )
        if let failure = failures.first {
            errorMessage = "Часть объектов не удалось удалить. «\(failure.url.lastPathComponent)»: \(failure.message)"
        }
    }

    /// Moves the files of the last deletion back and restores their subtrees.
    public func undoLastTrash() {
        guard !fileOperationInFlight, let entry = trash.popUndo() else { return }
        fileOperationInFlight = true

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
        fileOperationInFlight = false
        if !groups.isEmpty, let tree {
            let restored = tree.restoringSubtrees(groups: groups)
            self.tree = restored
            resetDuplicates()
            resetSimilar()
            addToCollection(collectionRoots)
            selection = []
            fileCount = restored.totalFiles
            folderCount = restored.directoryCount()
            if restored.isDeleted(currentIndex) {
                var cursor = currentIndex
                while cursor > 0, restored.isDeleted(cursor) {
                    cursor = restored.node(cursor).parent
                }
                currentIndex = max(cursor, 0)
            }
            rebuildCurrentRows()
            refreshVolumes()
            refreshDerived()
            invalidateCleanup()
            let bytes = groups.reduce(Int64(0)) { $0 + $1.bytes }
            showToast(
                "Возвращено: \(Plural.items(restoredCount)) · \(ByteFormat.string(bytes))",
                symbol: "arrow.uturn.backward"
            )
        }
        if let failure = failures.first {
            errorMessage = "Не удалось вернуть «\(failure.url.lastPathComponent)»: \(failure.message)"
        }
    }

    private func recordUndo(
        removal: ScanTreeRemoval,
        trashed: [(index: Int32, original: URL, trashed: URL)]
    ) {
        let roots = Array(Set(trashed.map(\.index)))
        trash.record(
            removal: removal,
            trashed: trashed,
            collectionRoots: roots.filter { collection.contains($0) }
        )
    }

    private func resetTrashUndo() {
        trash.reset()
    }

    // MARK: - Cleanup

    public func requestCleanup() {
        guard cleanup.canApply else { return }
        if cleanup.hasPermanentSelection
            || UserDefaults.standard.bool(forKey: AppSettingsKeys.confirmTrash) {
            cleanup.showConfirmation = true
        } else {
            confirmCleanup()
        }
    }

    public func confirmCleanup() {
        cleanup.showConfirmation = false
        guard !fileOperationInFlight, !isScanning, let tree else { return }
        let selected = cleanup.selectedSuggestions.filter { suggestion in
            suggestion.nodeIndex > 0
                && Int(suggestion.nodeIndex) < tree.count
                && !tree.isDeleted(suggestion.nodeIndex)
        }
        guard !selected.isEmpty else { return }
        fileOperationInFlight = true

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
                self.applyCleanup(
                    tree: tree,
                    trashed: trashed,
                    permanent: permanent,
                    failures: failures
                )
            }
        }
    }

    private func applyCleanup(
        tree scanTree: ScanTree,
        trashed: [(index: Int32, original: URL, trashed: URL)],
        permanent: [Int32],
        failures: [(url: URL, message: String)]
    ) {
        fileOperationInFlight = false
        let indices = trashed.map(\.index) + permanent
        guard !indices.isEmpty else {
            if let failure = failures.first {
                errorMessage = "Не удалось очистить «\(failure.url.lastPathComponent)»: \(failure.message)"
            }
            return
        }

        let removed = scanTree.removingSubtrees(at: indices)
        recordUndo(removal: removed, trashed: trashed)
        collection = collection.filter { !removed.tree.isDeleted($0) }
        resetDuplicates()
        resetSimilar()
        fileCount = removed.tree.totalFiles
        folderCount = removed.tree.directoryCount()
        tree = removed.tree
        selection = []
        if removed.tree.isDeleted(currentIndex) {
            var cursor = currentIndex
            while cursor > 0, removed.tree.isDeleted(cursor) {
                cursor = removed.tree.node(cursor).parent
            }
            currentIndex = max(cursor, 0)
        }
        rebuildCurrentRows()
        refreshVolumes()
        refreshDerived()
        invalidateCleanup()

        var text = "Очищено: \(Plural.items(indices.count)) · \(ByteFormat.string(removed.bytes))"
        if !permanent.isEmpty {
            text += " · безвозвратно: \(Plural.items(permanent.count))"
        }
        showToast(text, symbol: "sparkles")
        if let failure = failures.first {
            errorMessage = "Не удалось очистить «\(failure.url.lastPathComponent)»: \(failure.message)"
        }
    }

    func resetCleanup() {
        cleanup.reset()
    }

    private func invalidateCleanup() {
        resetCleanup()
        if tab == .cleanup {
            loadCleanupSuggestionsIfNeeded()
        }
    }

    // MARK: - Table rows

    public func rebuildCurrentRows() {
        guard let tree, Int(currentIndex) < tree.count else {
            currentRows = []
            currentRowsTotal = 0
            currentRowsTruncated = false
            return
        }
        let parentSize = max(tree.node(currentIndex).size, 1)
        var indices = tree.children(of: currentIndex)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            indices = indices.filter {
                tree.name(of: $0).localizedCaseInsensitiveContains(query)
            }
        }
        var rows: [ItemRow] = []
        rows.reserveCapacity(min(indices.count, rowLimit))
        for index in indices {
            // Paths are only needed by the "largest" list; skip them here to keep
            // huge folders (node_modules and friends) responsive.
            rows.append(ItemRowFactory.make(tree: tree, index: index, parentSize: parentSize, includePaths: false))
        }
        rows.sort(using: sortOrder)
        currentRowsTotal = rows.count
        currentRowsTruncated = rows.count > rowLimit
        if rows.count > rowLimit { rows = Array(rows.prefix(rowLimit)) }
        currentRows = rows
    }

    // MARK: - Type filter

    public func showFiles(of category: FileCategory) {
        categoryFilter = category
        tab = .largest
        searchText = ""
    }

    public func clearCategoryFilter() {
        categoryFilter = nil
    }

    // MARK: - Permissions

    public func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - UI helpers

    public func showToast(_ text: String, symbol: String = "checkmark.circle.fill") {
        toast = Toast(text: text, symbol: symbol)
        toastWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.toast = nil
        }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6, execute: item)
    }

    public func dismissError() {
        errorMessage = nil
    }

    public func dismissToast() {
        toastWorkItem?.cancel()
        toast = nil
    }

    // MARK: - Previews / snapshots

    public func loadPreview(tree: ScanTree) {
        scan.invalidate()
        scan.finish(tree)
        currentIndex = 0
        tab = .map
        selection = []
        resetTrashUndo()
        resetCleanup()
        resetCollection()
        search.reset()
        resetDuplicates()
        resetSimilar()
        fileCount = tree.totalFiles
        folderCount = tree.directoryCount()
        volumes = VolumeInfo.loadAll()
        rebuildCurrentRows()
        largestItems = tree.largestItems(limit: 4000).map {
            ItemRowFactory.make(tree: tree, index: $0, parentSize: max(tree.totalSize, 1), includePaths: true)
        }
        categoryStats = tree.categoryStats()
    }

    /// Fills cleanup state without running the advisor; used by snapshots.
    public func previewCleanup(suggestions: [CleanupSuggestion]) {
        cleanup.preview(suggestions)
    }

    /// Fills similar-image groups without running Vision; used by snapshots.
    public func previewSimilar(_ groups: [SimilarImageGroup]) {
        similarState = SimilarImageState()
        similarState.groups = groups
        similarState.candidateCount = groups.reduce(0) { $0 + $1.images.count }
        similarState.scannedCount = similarState.candidateCount
        similarState.progress = 1
    }

    /// Fills duplicate groups without hashing files; used by snapshots.
    public func previewDuplicates(_ groups: [DuplicateGroup]) {
        duplicates.preview(groups)
    }

    /// Fills disk overview state without scanning the real Trash; used by snapshots.
    public func previewDiskOverview(_ overview: DiskOverview) {
        disk.preview(overview)
    }

    public func previewScanning(path: String, progress: ScanProgress) {
        scan.previewScanning(path: path, progress: progress)
        currentIndex = 0
        resetTrashUndo()
        resetCleanup()
        resetCollection()
        search.reset()
        resetDuplicates()
        resetSimilar()
        volumes = VolumeInfo.loadAll()
    }

    public func previewWelcome() {
        scan.previewWelcome()
        currentIndex = 0
        resetTrashUndo()
        resetCleanup()
        resetCollection()
        search.reset()
        resetDuplicates()
        resetSimilar()
        volumes = VolumeInfo.loadAll()
    }

    public func previewSelect(index: Int32) {
        selection = [index]
    }

    public func previewNavigate(to index: Int32) {
        navigate(to: index)
    }
}

/// Keeps aggregate folders readable in tables and treemaps.
public enum TreeNaming {
    public static func name(tree: ScanTree, index: Int32) -> String {
        let node = tree.node(index)
        if node.nodeKind == .aggregate {
            return Plural.smallFiles(Int(node.itemCount))
        }
        let name = tree.name(of: index)
        if name.isEmpty {
            return index == 0 ? "Корень" : "Без имени"
        }
        return name
    }
}

extension AppModel {
    public var canExportReport: Bool { tree != nil }

    /// Shows a save panel and writes a CSV or HTML report of the current scan.
    public func exportReport(format: ReportFormat = .csv, scope: ReportScope = .currentFolder) {
        guard let tree else { return }

        let panel = NSSavePanel()
        panel.title = "Экспортировать отчёт"
        panel.message = "CSV или HTML. Отчёт строится по текущему скану и видимым фильтрам."
        panel.prompt = "Экспортировать"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .html]
        panel.nameFieldStringValue = defaultReportFilename(format: format, scope: scope)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let options = ReportOptions(
            format: format,
            scope: scope,
            search: searchText,
            category: categoryFilter,
            generatedAt: Date(),
            appVersion: appVersion
        )
        let rootIndex = currentIndex

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let text: String
                switch format {
                case .csv:
                    text = ReportExporter.makeCSV(tree: tree, rootIndex: rootIndex, options: options)
                case .html:
                    text = ReportExporter.makeHTML(tree: tree, rootIndex: rootIndex, options: options)
                }
                try ReportExporter.write(text, to: url)
                DispatchQueue.main.async {
                    self?.showToast("Отчёт сохранён: \(url.lastPathComponent)", symbol: "doc.text.fill")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Не удалось сохранить отчёт: \(error.localizedDescription)"
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func defaultReportFilename(format: ReportFormat, scope: ReportScope) -> String {
        let raw = scope == .currentFolder ? currentName : rootDisplayName
        var safe = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if safe.isEmpty { safe = "DiskScope" }
        return "DiskScope-\(safe).\(format.fileExtension)"
    }
}

extension AppModel {
    func runningBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private func topLevelSelection() -> [Int32] {
        guard let tree else { return [] }
        var result: [Int32] = []
        for index in selection.sorted() {
            guard index > 0, Int(index) < tree.count, !tree.isDeleted(index) else { continue }
            var ancestor = tree.node(index).parent
            var hasSelectedAncestor = false
            while ancestor >= 0 {
                if selection.contains(ancestor) {
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

extension AppModel {
    // MARK: - Inspector and file actions

    public var inspectorNode: Int32? {
        if selection.count == 1 { return selection.first }
        if selection.isEmpty { return currentIndex }
        return nil
    }

    public var canQuickLook: Bool {
        guard let tree else { return false }
        return selection.contains { index in
            index > 0 && Int(index) < tree.count
                && !tree.isDeleted(index)
                && tree.node(index).nodeKind == .file
        }
    }

    public func previewSelection() {
        guard let tree else { return }
        let index = selection.sorted().first { candidate in
            candidate > 0 && Int(candidate) < tree.count
                && !tree.isDeleted(candidate)
                && tree.node(candidate).nodeKind == .file
        }
        guard let index else {
            quickLookURL = nil
            return
        }
        previewNode(index)
    }

    public func previewNode(_ index: Int32) {
        guard let tree, index > 0, Int(index) < tree.count,
              !tree.isDeleted(index),
              tree.node(index).nodeKind == .file else { return }
        quickLookURL = tree.url(of: index)
    }

    public func copyPaths(_ indices: [Int32]) {
        guard let tree else { return }
        let paths = indices.compactMap { index -> String? in
            guard index >= 0, Int(index) < tree.count, !tree.isDeleted(index) else { return nil }
            return tree.path(of: index)
        }
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        showToast(
            paths.count == 1 ? "Путь скопирован" : "Скопировано путей: \(paths.count)",
            symbol: "doc.on.doc"
        )
    }

    public func openInTerminal(_ index: Int32) {
        guard let tree, index >= 0, Int(index) < tree.count, !tree.isDeleted(index) else { return }
        let url = tree.url(of: index)
        let folder = tree.isDirectory(index) ? url : url.deletingLastPathComponent()
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        guard FileManager.default.fileExists(atPath: terminal.path) else {
            errorMessage = "Не удалось найти Terminal.app"
            return
        }
        NSWorkspace.shared.open(
            [folder],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.errorMessage = "Не удалось открыть терминал: \(error.localizedDescription)"
            }
        }
    }
}

extension AppModel {
    public var freeSpaceText: String {
        guard let volume = internalVolume else { return "—" }
        return ByteFormat.string(volume.freeBytes)
    }

    public func refreshVolumes() {
        volumes = VolumeInfo.loadAll()
    }
}

extension AppModel {
    public var currentName: String {
        guard let tree else { return "" }
        if currentIndex == 0 { return rootDisplayName }
        let name = tree.name(of: currentIndex)
        return name.isEmpty ? rootDisplayName : name
    }

    public var breadcrumbs: [Int32] {
        guard let tree else { return [] }
        var chain: [Int32] = []
        var cursor = currentIndex
        while cursor >= 0, chain.count < 256 {
            chain.append(cursor)
            let parent = tree.node(cursor).parent
            if parent < 0 { break }
            cursor = parent
        }
        return chain.reversed()
    }

    public var canGoUp: Bool {
        guard let tree else { return false }
        return tree.node(currentIndex).parent >= 0
    }

    public var currentSize: Int64 {
        tree?.node(currentIndex).size ?? 0
    }

    public var currentItemCount: Int {
        Int(tree?.node(currentIndex).itemCount ?? 0)
    }

    public var currentDirectCount: Int {
        guard let tree, Int(currentIndex) < tree.count else { return 0 }
        return Int(tree.node(currentIndex).childrenCount)
    }

    public var currentPath: String {
        tree?.path(of: currentIndex) ?? ""
    }

    public var selectedSize: Int64 {
        guard let tree else { return 0 }
        return selection.reduce(Int64(0)) { $0 + tree.node($1).size }
    }

    public var selectedCount: Int { selection.count }

    public var canTrashSelection: Bool {
        guard let tree, !selection.isEmpty else { return false }
        return selection.allSatisfy { index in
            index > 0 && !tree.isDeleted(index) && tree.node(index).nodeKind != .aggregate
        }
    }

    public var canRevealSelection: Bool {
        guard let tree, !selection.isEmpty else { return false }
        return selection.contains { !tree.isDeleted($0) }
    }

    public var hasPermissionIssues: Bool {
        (tree?.report.skippedItems ?? 0) > 0
    }

    public var isScanning: Bool { phase == .scanning }

    public var volume: VolumeInfo? {
        volumes.first(where: { $0.isInternal }) ?? volumes.first
    }

    public var internalVolume: VolumeInfo? {
        volumes.first(where: { $0.path == "/" }) ?? volumes.first
    }

    public var currentNode: ScanNode? {
        guard let tree, currentIndex >= 0, Int(currentIndex) < tree.count else { return nil }
        return tree.node(currentIndex)
    }

    public var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    public var rootDisplayName: String {
        guard let tree else { return "DiskScope" }
        if tree.rootPath == "/" { return internalVolume?.name ?? "Macintosh HD" }
        let known: [String: String] = [
            homePath: "Домашняя папка",
            homePath + "/Applications": "Программы",
            "/Applications": "Программы",
            homePath + "/Downloads": "Загрузки",
            homePath + "/Documents": "Документы",
            homePath + "/Desktop": "Рабочий стол",
            homePath + "/Library": "Библиотека",
            homePath + "/Movies": "Видео",
            homePath + "/Music": "Музыка",
            homePath + "/Pictures": "Изображения",
        ]
        if let known = known[tree.rootPath] { return known }
        let name = URL(fileURLWithPath: tree.rootPath).lastPathComponent
        return name.isEmpty ? tree.rootPath : name
    }
}
