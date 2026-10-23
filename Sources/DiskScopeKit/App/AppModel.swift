import AppKit
import Combine
import Foundation

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

    @Published public internal(set) var scan: ScanController
    @Published public internal(set) var nav = NavigationModel()
    @Published public internal(set) var browser = BrowserModel()
    @Published public var tab: Tab = .map {
        didSet {
            if tab == .cleanup {
                loadCleanupSuggestionsIfNeeded()
            }
        }
    }

    @Published public internal(set) var volumes: [VolumeInfo] = VolumeInfo.loadAll()
    @Published public internal(set) var fileCount = 0
    @Published public internal(set) var folderCount = 0
    @Published public private(set) var media = MediaModel()

    @Published public var toast: Toast?
    @Published public var errorMessage: String?
    @Published public var showCommandPalette = false
    @Published public var showPermissionSheet = false
    @Published public internal(set) var trash = TrashModel()
    @Published public internal(set) var trashOperations = TrashOperationsModel()
    @Published public internal(set) var cleanup = CleanupModel()
    @Published public internal(set) var cleanupOperations = CleanupOperationsModel()
    @Published public internal(set) var collection: Set<Int32> = []
    @Published public var showCollection = false
    @Published public internal(set) var search = SearchModel()
    @Published public internal(set) var disk = DiskModel()
    @Published public internal(set) var history: HistoryModel
    @Published public internal(set) var duplicates = DuplicatesModel()
    @Published public internal(set) var similar = SimilarModel()
    @Published public internal(set) var inspector = InspectorModel()
    @Published public internal(set) var report = ReportModel()
    @Published public internal(set) var preview = PreviewModel()
    @Published public internal(set) var stats = DerivedStatsModel()
    @Published public var showInspector = false

    @Published public internal(set) var budget = BudgetModel()

    private var toastWorkItem: DispatchWorkItem?
    private var cleanupCancellable: AnyCancellable?
    private var diskCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var searchCancellable: AnyCancellable?

    public init(services: AppServices = .live) {
        scan = ScanController(cache: services.cache, scannerFactory: services.scannerFactory)
        history = HistoryModel(store: services.historyStore)
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
                    homePath: self.browser.homePath,
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
        similar.attach { [weak self] in self?.tree }
        similar.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        nav.attach { [weak self] in self?.tree }
        nav.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        browser.attach(appModel: self)
        browser.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        inspector.attach(
            treeProvider: { [weak self] in self?.tree },
            currentIndexProvider: { [weak self] in self?.currentIndex ?? 0 },
            selectionProvider: { [weak self] in self?.selection ?? [] },
            toast: { [weak self] text, symbol in self?.showToast(text, symbol: symbol) },
            error: { [weak self] message in self?.errorMessage = message }
        )
        inspector.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        report.attach(
            treeProvider: { [weak self] in self?.tree },
            currentIndexProvider: { [weak self] in self?.currentIndex ?? 0 },
            searchProvider: { [weak self] in self?.searchText ?? "" },
            categoryProvider: { [weak self] in self?.categoryFilter },
            currentNameProvider: { [weak self] in self?.browser.currentName ?? "" },
            rootDisplayNameProvider: { [weak self] in self?.browser.rootDisplayName ?? "DiskScope" },
            toast: { [weak self] text, symbol in self?.showToast(text, symbol: symbol) },
            error: { [weak self] message in self?.errorMessage = message }
        )
        report.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        trash.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        trashOperations.attach(appModel: self)
        trashOperations.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        cleanupOperations.attach(appModel: self)
        cleanupOperations.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        disk.attach { [weak self] in self?.browser.internalVolume }
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
        preview.attach(appModel: self)
        preview.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        stats.attach(
            treeProvider: { [weak self] in self?.tree },
            categoryProvider: { [weak self] in self?.categoryFilter },
            searchProvider: { [weak self] in self?.searchText ?? "" }
        )
        stats.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
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

    public var currentIndex: Int32 {
        get { nav.currentIndex }
        set { nav.currentIndex = newValue }
    }

    public var selection: Set<Int32> {
        get { nav.selection }
        set { nav.selection = newValue }
    }

    public var currentRows: [ItemRow] { nav.rows }
    public var currentRowsTotal: Int { nav.rowsTotal }
    public var currentRowsTruncated: Bool { nav.rowsTruncated }

    public var searchText: String {
        get { nav.searchText }
        set { nav.searchText = newValue }
    }

    public var sortOrder: [KeyPathComparator<ItemRow>] {
        get { nav.sortOrder }
        set { nav.sortOrder = newValue }
    }

    public var categoryFilter: FileCategory? {
        get { nav.categoryFilter }
        set { nav.categoryFilter = newValue }
    }

    // MARK: - Inspector compatibility

    public var inspectorNode: Int32? { inspector.inspectorNode }
    public var canQuickLook: Bool { inspector.canQuickLook }
    public var quickLookURL: URL? {
        get { inspector.quickLookURL }
        set { inspector.quickLookURL = newValue }
    }

    public func previewSelection() {
        inspector.previewSelection()
    }

    public func previewNode(_ index: Int32) {
        inspector.previewNode(index)
    }

    public func copyPaths(_ indices: [Int32]) {
        inspector.copyPaths(indices)
    }

    public func openInTerminal(_ index: Int32) {
        inspector.openInTerminal(index)
    }

    // MARK: - Report compatibility

    public var canExportReport: Bool { report.canExportReport }

    public func exportReport(format: ReportFormat = .csv, scope: ReportScope = .currentFolder) {
        report.exportReport(format: format, scope: scope)
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

        let cacheDirectory = scan.cacheDirectory
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
            scan(path: browser.homePath)
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
        nav.reset()
        tab = .map
        fileCount = result.totalFiles
        folderCount = result.directoryCount()
        browser.refreshVolumes()
        nav.rebuild()
        stats.refresh()
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

    // MARK: - Navigation

    public func navigate(to index: Int32) {
        nav.navigate(to: index)
    }

    public func goUp() {
        nav.goUp()
    }

    public func goToRoot() {
        nav.navigate(to: 0)
    }

    // MARK: - Trash

    func resetTrashUndo() {
        trash.reset()
    }

    // MARK: - Cleanup

    func resetCleanup() {
        cleanup.reset()
    }

    func invalidateCleanup() {
        resetCleanup()
        if tab == .cleanup {
            loadCleanupSuggestionsIfNeeded()
        }
    }

    // MARK: - Table rows

    public func rebuildCurrentRows() {
        nav.rebuild()
    }

    // MARK: - Type filter

    public func showFiles(of category: FileCategory) {
        tab = .largest
        nav.showFiles(of: category)
    }

    public func clearCategoryFilter() {
        nav.clearCategoryFilter()
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
    func runningBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

extension AppModel {
    public var isScanning: Bool { phase == .scanning }
}
