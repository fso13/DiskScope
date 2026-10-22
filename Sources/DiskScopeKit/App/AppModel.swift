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

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .map: return "Карта"
            case .largest: return "Крупнейшие"
            case .types: return "Типы файлов"
            case .media: return "Медиа"
            case .cleanup: return "Очистка"
            case .disk: return "Диск"
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

    @Published public private(set) var phase: Phase = .welcome
    @Published public private(set) var tree: ScanTree?
    @Published public private(set) var currentIndex: Int32 = 0
    @Published public var tab: Tab = .map {
        didSet {
            if tab == .cleanup {
                loadCleanupSuggestionsIfNeeded()
            }
        }
    }
    @Published public var selection: Set<Int32> = []
    @Published public private(set) var progress: ScanProgress?
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
    @Published public var showTrashConfirmation = false
    @Published public var showPermissionSheet = false
    @Published public private(set) var canUndoTrash = false
    @Published public private(set) var cleanupSuggestions: [CleanupSuggestion] = []
    @Published public var cleanupSelection: Set<String> = []
    @Published public private(set) var cleanupLoading = false
    @Published public var showCleanupConfirmation = false
    @Published public private(set) var collection: Set<Int32> = []
    @Published public var showCollection = false
    @Published public var showCollectionTrashConfirmation = false
    @Published public var showGlobalSearch = false {
        didSet {
            if showGlobalSearch {
                ensureSearchIndex()
                scheduleSearch()
            }
        }
    }
    @Published public var globalSearchText = "" {
        didSet { scheduleSearch() }
    }
    @Published public var searchMinimumSize: Int64 = 0 {
        didSet { scheduleSearch() }
    }
    @Published public var searchCategory: FileCategory? {
        didSet { scheduleSearch() }
    }
    @Published public var searchKind: SearchKind = .any {
        didSet { scheduleSearch() }
    }
    @Published public var searchDateRange: SearchDateRange = .any {
        didSet { scheduleSearch() }
    }
    @Published public var searchSort: SearchSort = .size {
        didSet { scheduleSearch() }
    }
    @Published public private(set) var searchHits: [SearchHit] = []
    @Published public private(set) var searchTotal = 0
    @Published public private(set) var searchIndexing = false
    @Published public private(set) var searchReady = false
    @Published public private(set) var diskOverview: DiskOverview?
    @Published public private(set) var diskOverviewLoading = false
    @Published public private(set) var diskOverviewError: String?
    @Published public var showInspector = false
    @Published public var quickLookURL: URL?
    @Published public private(set) var lastScanPath: String? = UserDefaults.standard.string(forKey: "lastScanPath")

    private var cancellation: ScanCancellation?
    private var activeScanID = UUID()
    private let scanQueue = DispatchQueue(label: "ru.diskscope.scan", qos: .userInitiated)
    private var toastWorkItem: DispatchWorkItem?
    private var derivedGeneration = 0
    private let rowLimit = 2500
    private var trashUndoStack: [TrashUndoEntry] = []
    private var fileOperationInFlight = false
    private var cleanupGeneration = 0
    private var cleanupTreeID: ObjectIdentifier?
    private var searchIndex: ScanSearchIndex?
    private var searchIndexGeneration = 0
    private var searchQueryGeneration = 0
    private var searchWorkItem: DispatchWorkItem?

    public init() {
        UserDefaults.standard.register(defaults: [
            AppSettingsKeys.appearance: AppAppearance.system.rawValue,
            AppSettingsKeys.confirmTrash: true,
        ])
        media.attach(appModel: self)
    }

    // MARK: - Derived state

    public var isScanning: Bool { phase == .scanning }

    public var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    public var volume: VolumeInfo? {
        volumes.first(where: { $0.isInternal }) ?? volumes.first
    }

    public var internalVolume: VolumeInfo? {
        volumes.first(where: { $0.path == "/" }) ?? volumes.first
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

    public var currentNode: ScanNode? {
        guard let tree, currentIndex >= 0, Int(currentIndex) < tree.count else { return nil }
        return tree.node(currentIndex)
    }

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

        cancellation?.cancel()
        let token = ScanCancellation()
        cancellation = token
        activeScanID = UUID()
        let scanID = activeScanID

        phase = .scanning
        progress = ScanProgress(currentPath: standardized)
        selection = []
        categoryFilter = nil
        searchText = ""
        resetTrashUndo()
        resetCleanup()
        resetCollection()
        resetSearch()
        lastScanPath = standardized
        UserDefaults.standard.set(standardized, forKey: "lastScanPath")

        let options = ScanOptions()
        scanQueue.async { [weak self] in
            guard let self else { return }
            let scanner = DiskScanner(options: options)
            do {
                let result = try scanner.scan(path: standardized, cancellation: token, progress: { update in
                    DispatchQueue.main.async {
                        guard self.activeScanID == scanID else { return }
                        self.progress = update
                    }
                })
                DispatchQueue.main.async {
                    guard self.activeScanID == scanID else { return }
                    self.finishScan(result)
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.activeScanID == scanID else { return }
                    self.failScan(error, wasCancelled: token.isCancelled)
                }
            }
        }
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
        cancellation?.cancel()
        cancellation = nil
        activeScanID = UUID()
        progress = nil
        phase = tree == nil ? .welcome : .ready
        if tab == .cleanup {
            loadCleanupSuggestionsIfNeeded()
        }
    }

    public func chooseFolder() {
        guard !isScanning else { return }
        let panel = NSOpenPanel()
        panel.title = "Выберите папку для анализа"
        panel.message = "DiskScope посчитает, что занимает место внутри выбранной папки."
        panel.prompt = "Сканировать"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url {
            scan(path: url.path)
        }
    }

    public func scanHome() {
        scan(path: homePath)
    }

    public func scanVolume(_ volume: VolumeInfo) {
        scan(path: volume.path)
    }

    private func finishScan(_ result: ScanTree) {
        tree = result
        phase = .ready
        progress = nil
        currentIndex = 0
        selection = []
        tab = .map
        fileCount = result.totalFiles
        folderCount = result.directoryCount()
        refreshVolumes()
        rebuildCurrentRows()
        refreshDerived()
    }

    private func failScan(_ error: Error, wasCancelled: Bool) {
        progress = nil
        if wasCancelled {
            phase = tree == nil ? .welcome : .ready
            return
        }
        phase = .failed(error.localizedDescription)
        errorMessage = error.localizedDescription
    }

    private func refreshDerived() {
        guard let tree else { return }
        derivedGeneration += 1
        let generation = derivedGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = tree.largestItems(limit: 4000)
            let rows = items.map { index in
                Self.makeRow(tree: tree, index: index, parentSize: max(tree.totalSize, 1), includePaths: true)
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
        guard !fileOperationInFlight, let entry = trashUndoStack.popLast() else { return }
        canUndoTrash = !trashUndoStack.isEmpty
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
        var files: [TrashUndoFile] = []
        for item in trashed {
            guard let group = removal.groups.first(where: { $0.root == item.index }) else { continue }
            files.append(TrashUndoFile(
                originalURL: item.original,
                trashedURL: item.trashed,
                group: group
            ))
        }
        guard !files.isEmpty else { return }
        let roots = Array(Set(files.map { $0.group.root }))
        let collectionRoots = roots.filter { collection.contains($0) }
        trashUndoStack.append(TrashUndoEntry(files: files, collectionRoots: collectionRoots))
        if trashUndoStack.count > 10 {
            trashUndoStack.removeFirst()
        }
        canUndoTrash = true
    }

    private func resetTrashUndo() {
        trashUndoStack.removeAll()
        canUndoTrash = false
    }

    // MARK: - Cleanup

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
            DispatchQueue.main.async {
                guard let self,
                      self.cleanupGeneration == generation,
                      let current = self.tree,
                      current === tree else { return }
                self.cleanupSuggestions = suggestions
                self.cleanupSelection = Set(
                    suggestions.filter { $0.isSelectedByDefault }.map(\.id)
                )
                self.cleanupLoading = false
            }
        }
    }

    public func requestCleanup() {
        guard cleanupCanApply else { return }
        if cleanupHasPermanentSelection
            || UserDefaults.standard.bool(forKey: AppSettingsKeys.confirmTrash) {
            showCleanupConfirmation = true
        } else {
            confirmCleanup()
        }
    }

    public func confirmCleanup() {
        showCleanupConfirmation = false
        guard !fileOperationInFlight, !isScanning, let tree else { return }
        let selected = cleanupSelectedSuggestions.filter { suggestion in
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

    private func resetCleanup() {
        cleanupGeneration += 1
        cleanupSuggestions = []
        cleanupSelection = []
        cleanupLoading = false
        cleanupTreeID = nil
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
            rows.append(Self.makeRow(tree: tree, index: index, parentSize: parentSize, includePaths: false))
        }
        rows.sort(using: sortOrder)
        currentRowsTotal = rows.count
        currentRowsTruncated = rows.count > rowLimit
        if rows.count > rowLimit { rows = Array(rows.prefix(rowLimit)) }
        currentRows = rows
    }

    private static func makeRow(
        tree: ScanTree,
        index: Int32,
        parentSize: Int64,
        includePaths: Bool
    ) -> ItemRow {
        let node = tree.node(index)
        let isAggregate = node.nodeKind == .aggregate
        let name: String
        if isAggregate {
            name = "Мелкие файлы"
        } else {
            name = TreeNaming.name(tree: tree, index: index)
        }
        return ItemRow(
            id: index,
            name: name,
            path: includePaths ? tree.path(of: index) : "",
            relativePath: includePaths ? tree.relativePath(of: index) : "",
            size: node.size,
            category: tree.category(of: index),
            isContainer: node.nodeKind.isContainer,
            isAggregate: isAggregate,
            itemCount: Int(node.itemCount),
            fraction: parentSize > 0 ? Double(node.size) / Double(parentSize) : 0,
            depth: 0
        )
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
        activeScanID = UUID()
        cancellation?.cancel()
        self.tree = tree
        phase = .ready
        currentIndex = 0
        progress = nil
        tab = .map
        selection = []
        resetTrashUndo()
        resetCleanup()
        resetCollection()
        resetSearch()
        fileCount = tree.totalFiles
        folderCount = tree.directoryCount()
        volumes = VolumeInfo.loadAll()
        rebuildCurrentRows()
        largestItems = tree.largestItems(limit: 4000).map {
            Self.makeRow(tree: tree, index: $0, parentSize: max(tree.totalSize, 1), includePaths: true)
        }
        categoryStats = tree.categoryStats()
    }

    /// Fills cleanup state without running the advisor; used by snapshots.
    public func previewCleanup(suggestions: [CleanupSuggestion]) {
        cleanupGeneration += 1
        cleanupSuggestions = suggestions
        cleanupSelection = Set(suggestions.filter { $0.isSelectedByDefault }.map(\.id))
        cleanupLoading = false
        cleanupTreeID = tree.map { ObjectIdentifier($0) }
    }

    /// Fills disk overview state without scanning the real Trash; used by snapshots.
    public func previewDiskOverview(_ overview: DiskOverview) {
        diskOverview = overview
        diskOverviewLoading = false
        diskOverviewError = nil
    }

    public func previewScanning(path: String, progress: ScanProgress) {
        tree = nil
        phase = .scanning
        currentIndex = 0
        self.progress = progress
        resetTrashUndo()
        resetCleanup()
        resetCollection()
        resetSearch()
        volumes = VolumeInfo.loadAll()
    }

    public func previewWelcome() {
        tree = nil
        phase = .welcome
        progress = nil
        currentIndex = 0
        resetTrashUndo()
        resetCleanup()
        resetCollection()
        resetSearch()
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

private struct TrashUndoFile: Sendable {
    let originalURL: URL
    let trashedURL: URL
    let group: ScanTreeRemoval.Group
}

private struct TrashUndoEntry: Sendable {
    let files: [TrashUndoFile]
    let collectionRoots: [Int32]
}

extension AppModel {
    // MARK: - Cleanup state

    public var cleanupSelectedSuggestions: [CleanupSuggestion] {
        cleanupSuggestions.filter { cleanupSelection.contains($0.id) }
    }

    public var cleanupSelectedSize: Int64 {
        cleanupSelectedSuggestions.reduce(Int64(0)) { $0 + $1.size }
    }

    public var cleanupSelectedCount: Int {
        cleanupSelectedSuggestions.count
    }

    public var cleanupTotalSize: Int64 {
        cleanupSuggestions.reduce(Int64(0)) { $0 + $1.size }
    }

    public var cleanupCanApply: Bool {
        !cleanupSelection.isEmpty && !cleanupLoading && !fileOperationInFlight
    }

    public var cleanupHasPermanentSelection: Bool {
        cleanupSelectedSuggestions.contains { $0.disposition == .deletePermanently }
    }

    public var cleanupConfirmationMessage: String {
        let selected = cleanupSelectedSuggestions
        let size = ByteFormat.string(selected.reduce(Int64(0)) { $0 + $1.size })
        if cleanupHasPermanentSelection {
            return "\(Plural.items(selected.count)) · \(size). Среди них есть объекты, которые удаляются безвозвратно; отменить это через ⌘Z не получится."
        }
        return "\(Plural.items(selected.count)) · \(size). Файлы можно вернуть из Корзины через ⌘Z."
    }

    public func toggleCleanupSelection(_ id: String) {
        var updated = cleanupSelection
        if !updated.insert(id).inserted {
            updated.remove(id)
        }
        cleanupSelection = updated
    }

    public func selectAllSafeCleanup() {
        var updated = cleanupSelection
        for suggestion in cleanupSuggestions where suggestion.isSelectedByDefault {
            updated.insert(suggestion.id)
        }
        cleanupSelection = updated
    }

    public func selectCleanup(_ suggestions: [CleanupSuggestion]) {
        var updated = cleanupSelection
        for suggestion in suggestions {
            updated.insert(suggestion.id)
        }
        cleanupSelection = updated
    }

    public func clearCleanupSelection() {
        cleanupSelection = []
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
    // MARK: - Collection

    public var collectionCount: Int { collection.count }

    public var collectionSize: Int64 {
        guard let tree else { return 0 }
        return collection.reduce(Int64(0)) { total, index in
            Int(index) < tree.count ? total + tree.node(index).size : total
        }
    }

    public var collectionSummary: String {
        "\(Plural.items(collectionCount)) · \(ByteFormat.string(collectionSize))"
    }

    public var collectionTrashMessage: String {
        "\(collectionSummary). Файлы можно вернуть из Корзины через ⌘Z."
    }

    public var collectionRows: [ItemRow] {
        guard let tree else { return [] }
        return collection.compactMap { index -> ItemRow? in
            guard index > 0, Int(index) < tree.count, !tree.isDeleted(index) else { return nil }
            return Self.makeRow(
                tree: tree,
                index: index,
                parentSize: max(tree.totalSize, 1),
                includePaths: true
            )
        }
        .sorted { $0.size > $1.size }
    }

    public var canTrashCollection: Bool {
        !collection.isEmpty && !fileOperationInFlight
    }

    public func isInCollection(_ index: Int32) -> Bool {
        collection.contains(index)
    }

    public func addToCollection(_ indices: [Int32]) {
        guard let tree else { return }
        var updated = collection
        for index in indices {
            guard index > 0, Int(index) < tree.count, !tree.isDeleted(index) else { continue }
            guard tree.node(index).nodeKind != .aggregate else { continue }
            if updated.contains(where: { isAncestor($0, of: index, in: tree) }) { continue }
            updated = updated.filter { !isAncestor(index, of: $0, in: tree) }
            updated.insert(index)
        }
        collection = updated
    }

    public func removeFromCollection(_ indices: [Int32]) {
        collection.subtract(indices)
    }

    public func toggleCollection(_ indices: [Int32]) {
        guard !indices.isEmpty else { return }
        if indices.allSatisfy({ collection.contains($0) }) {
            removeFromCollection(indices)
        } else {
            addToCollection(indices)
        }
    }

    public func clearCollection() {
        collection = []
    }

    public func requestTrashCollection() {
        guard canTrashCollection else { return }
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.confirmTrash) {
            showCollectionTrashConfirmation = true
        } else {
            confirmCollectionTrash()
        }
    }

    private func isAncestor(_ ancestor: Int32, of node: Int32, in tree: ScanTree) -> Bool {
        var cursor = tree.node(node).parent
        while cursor >= 0 {
            if cursor == ancestor { return true }
            cursor = tree.node(cursor).parent
        }
        return false
    }

    func resetCollection() {
        collection = []
        showCollection = false
        showCollectionTrashConfirmation = false
    }
}

extension AppModel {
    // MARK: - Global search

    /// Builds the name index on demand. Results are applied only for the current tree.
    public func ensureSearchIndex() {
        guard let tree else {
            resetSearch()
            return
        }
        if let index = searchIndex, index.treeIdentifier == ObjectIdentifier(tree) {
            searchReady = true
            return
        }
        guard !searchIndexing else { return }

        searchIndexGeneration += 1
        let generation = searchIndexGeneration
        searchIndexing = true
        searchReady = false
        let treeToIndex = tree

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let index = ScanSearchIndex(tree: treeToIndex)
            DispatchQueue.main.async {
                guard let self,
                      self.searchIndexGeneration == generation,
                      self.tree === treeToIndex else { return }
                self.searchIndex = index
                self.searchIndexing = false
                self.searchReady = true
                self.runSearch()
            }
        }
    }

    func scheduleSearch() {
        searchWorkItem?.cancel()
        guard showGlobalSearch else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.runSearch()
        }
        searchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    func runSearch() {
        guard showGlobalSearch, let tree else { return }
        guard let index = searchIndex, index.treeIdentifier == ObjectIdentifier(tree) else {
            ensureSearchIndex()
            return
        }

        let query = SearchQuery(
            text: globalSearchText,
            minimumSize: searchMinimumSize,
            category: searchCategory,
            kind: searchKind,
            dateRange: searchDateRange,
            sort: searchSort,
            limit: 500
        )
        searchQueryGeneration += 1
        let generation = searchQueryGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = index.search(query)
            DispatchQueue.main.async {
                guard let self,
                      self.searchQueryGeneration == generation,
                      self.showGlobalSearch else { return }
                self.searchHits = results.hits
                self.searchTotal = results.total
            }
        }
    }

    func resetSearch() {
        searchIndexGeneration += 1
        searchQueryGeneration += 1
        searchWorkItem?.cancel()
        searchIndex = nil
        searchHits = []
        searchTotal = 0
        searchIndexing = false
        searchReady = false
        showGlobalSearch = false
        globalSearchText = ""
    }

    public func revealSearchHit(_ hit: SearchHit) {
        showGlobalSearch = false
        reveal(indices: [hit.index])
    }

    public func navigateToSearchHit(_ hit: SearchHit) {
        guard let tree, hit.index > 0, Int(hit.index) < tree.count else { return }
        showGlobalSearch = false
        let node = tree.node(hit.index)
        if node.nodeKind.isContainer {
            navigate(to: hit.index)
        } else {
            if node.parent >= 0 {
                navigate(to: node.parent)
            }
            reveal(indices: [hit.index])
        }
    }

    public func addSearchHitToCollection(_ hit: SearchHit) {
        addToCollection([hit.index])
        showToast("В коллекции: \(collectionSummary)", symbol: "tray.full")
    }

    public func requestTrashSearchHit(_ hit: SearchHit) {
        guard let tree, hit.index > 0, Int(hit.index) < tree.count, !tree.isDeleted(hit.index) else {
            return
        }
        showGlobalSearch = false
        selection = [hit.index]
        // Let the search sheet finish dismissing before showing the confirmation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.requestTrashSelection()
        }
    }
}

extension AppModel {
    private func runningBundleIdentifiers() -> Set<String> {
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
    // MARK: - Disk overview

    public func refreshDiskOverview(force: Bool = false) {
        guard !diskOverviewLoading else { return }
        if !force, let diskOverview, Date().timeIntervalSince(diskOverview.updatedAt) < 60 {
            return
        }
        guard let volume = internalVolume else {
            diskOverviewError = "Не удалось определить внутренний диск"
            return
        }
        diskOverviewLoading = true
        diskOverviewError = nil
        let trashURL = DiskOverviewService.defaultTrashURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let overview = DiskOverviewService.load(volume: volume, trashURL: trashURL)
            DispatchQueue.main.async {
                guard let self else { return }
                self.diskOverview = overview
                self.diskOverviewLoading = false
            }
        }
    }

    public func showDiskOverview() {
        tab = .disk
        refreshDiskOverview(force: true)
    }

    public func openTrash() {
        let url = diskOverview?.trash.url ?? DiskOverviewService.defaultTrashURL
        NSWorkspace.shared.open(url)
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
