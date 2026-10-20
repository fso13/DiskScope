import AppKit
import Combine
import Foundation

/// State and actions for the "Медиа" tab. Kept separate from AppModel so the
/// media search can have its own folders, filters and selection.
@MainActor
public final class MediaModel: ObservableObject {
    public struct OperationProgress: Equatable, Sendable {
        public let done: Int
        public let total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }

        public var fraction: Double {
            total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0
        }
    }

    weak var appModel: AppModel?
    private var didSeedSources = false
    private var cancellation: ScanCancellation?
    private var activeSearchID = UUID()
    private let workQueue = DispatchQueue(label: "ru.diskscope.media", qos: .userInitiated)

    @Published public private(set) var sources: [URL] = []
    @Published public private(set) var types: Set<MediaType> = MediaType.broad
    @Published public private(set) var results: [MediaFile] = []
    @Published public var selectedIDs: Set<String> = []
    @Published public var resultFilter = ""
    @Published public private(set) var isSearching = false
    @Published public private(set) var progress: MediaSearchProgress?
    @Published public private(set) var hasSearched = false
    @Published public private(set) var searchDuration: TimeInterval = 0
    @Published public private(set) var skippedItems = 0
    @Published public private(set) var truncated = false
    @Published public var destination: URL?
    @Published public private(set) var isMoving = false
    @Published public private(set) var moveProgress: OperationProgress?
    @Published public private(set) var isImportingToPhotos = false
    @Published public private(set) var photosProgress: OperationProgress?
    @Published public var showPhotosAccessAlert = false

    public init() {}

    func attach(appModel: AppModel) {
        self.appModel = appModel
    }

    // MARK: - Derived state

    public var filteredResults: [MediaFile] {
        let query = resultFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return results }
        return results.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.relativePath.localizedCaseInsensitiveContains(query)
        }
    }

    public var resultsBytes: Int64 {
        results.reduce(Int64(0)) { $0 + $1.size }
    }

    public var filteredBytes: Int64 {
        filteredResults.reduce(Int64(0)) { $0 + $1.size }
    }

    public var selectedFiles: [MediaFile] {
        results.filter { selectedIDs.contains($0.id) }
    }

    public var selectedSize: Int64 {
        selectedFiles.reduce(Int64(0)) { $0 + $1.size }
    }

    public var selectedImageFiles: [MediaFile] {
        selectedFiles.filter { $0.kind == .image }
    }

    public var selectedPhotosFiles: [MediaFile] {
        selectedFiles.filter(PhotosImporter.supports)
    }

    public var selectedPhotosCount: Int { selectedPhotosFiles.count }
    public var selectedImageCount: Int { selectedImageFiles.count }

    public var isBusy: Bool {
        isSearching || isMoving || isImportingToPhotos
    }

    public var canSearch: Bool {
        !isBusy && !sources.isEmpty && !types.isEmpty
    }

    public var canMove: Bool {
        !isBusy && !selectedFiles.isEmpty && destination != nil
    }

    public var canImportToPhotos: Bool {
        !isBusy && !selectedPhotosFiles.isEmpty
    }

    public var destinationName: String {
        guard let destination else { return "" }
        let name = destination.lastPathComponent
        return name.isEmpty ? destination.path : name
    }

    public var destinationPath: String {
        destination?.path ?? ""
    }

    // MARK: - Sources

    /// Seeds the search with the folder that was just scanned. Called when the
    /// Медиа tab appears; the user can add more folders or remove this one.
    public func seedCurrentFolder(_ path: String?) {
        guard !didSeedSources else { return }
        didSeedSources = true
        guard sources.isEmpty, let path, !path.isEmpty else { return }
        addSource(URL(fileURLWithPath: path))
    }

    public func addSource(_ url: URL) {
        guard !isBusy else { return }
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            reportError("«\(standardized.lastPathComponent)» не является папкой.")
            return
        }
        guard !sources.contains(where: { $0.standardizedFileURL.path == standardized.path }) else {
            return
        }
        sources.append(standardized)
        invalidateResults()
    }

    public func addCurrentFolder(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        addSource(URL(fileURLWithPath: path))
    }

    public func removeSource(_ url: URL) {
        guard !isBusy else { return }
        let path = url.standardizedFileURL.path
        sources.removeAll { $0.standardizedFileURL.path == path }
        invalidateResults()
    }

    public func chooseSources() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Папки для медиа-поиска"
        panel.message = "DiskScope будет искать выбранные типы файлов внутри этих папок."
        panel.prompt = "Добавить"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = sources.last ?? FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addSource(url)
        }
    }

    // MARK: - Types

    public func setTypes(_ newTypes: Set<MediaType>) {
        guard !isBusy else { return }
        types = newTypes
        invalidateResults()
    }

    public func toggleType(_ type: MediaType) {
        guard !isBusy else { return }
        if types.contains(type) {
            types.remove(type)
        } else {
            types.insert(type)
        }
        invalidateResults()
    }

    public func selectAllTypes() {
        guard !isBusy else { return }
        types = Set(MediaType.allCases)
        invalidateResults()
    }

    public func clearTypes() {
        guard !isBusy else { return }
        types = []
        invalidateResults()
    }

    // MARK: - Destination

    public func chooseDestination() {
        guard !isMoving && !isImportingToPhotos else { return }
        let panel = NSOpenPanel()
        panel.title = "Куда перенести файлы"
        panel.message = "Выберите папку назначения. Существующие файлы с такими именами получат суффикс."
        panel.prompt = "Выбрать"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination ?? FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url.standardizedFileURL
    }

    // MARK: - Search

    public func search() {
        guard !isBusy else { return }
        guard !sources.isEmpty else {
            reportError(MediaSearchError.noFolders.localizedDescription)
            return
        }
        guard !types.isEmpty else {
            reportError(MediaSearchError.noTypes.localizedDescription)
            return
        }

        let options = MediaSearchOptions(folders: sources, types: types)
        let token = ScanCancellation()
        cancellation = token
        activeSearchID = UUID()
        let searchID = activeSearchID

        isSearching = true
        hasSearched = true
        results = []
        selectedIDs = []
        resultFilter = ""
        skippedItems = 0
        truncated = false
        searchDuration = 0
        progress = MediaSearchProgress(currentPath: sources.first?.path ?? "", elapsed: 0)

        workQueue.async { [weak self] in
            let engine = MediaSearchEngine()
            do {
                let result = try engine.search(
                    options: options,
                    cancellation: token,
                    progress: { update in
                        DispatchQueue.main.async {
                            guard let self, self.activeSearchID == searchID else { return }
                            self.progress = update
                        }
                    }
                )
                DispatchQueue.main.async {
                    guard let self, self.activeSearchID == searchID else { return }
                    self.finishSearch(result)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.activeSearchID == searchID else { return }
                    self.failSearch(error)
                }
            }
        }
    }

    public func cancelSearch() {
        cancellation?.cancel()
        cancellation = nil
        activeSearchID = UUID()
        isSearching = false
        progress = nil
    }

    private func finishSearch(_ result: MediaSearchResult) {
        isSearching = false
        cancellation = nil
        progress = nil
        results = result.files
        skippedItems = result.skippedItems
        truncated = result.truncated
        searchDuration = result.duration
        selectedIDs = []

        if result.files.isEmpty {
            appModel?.showToast("Ничего не найдено", symbol: "magnifyingglass")
        } else {
            appModel?.showToast(
                "Найдено \(Plural.files(result.files.count)) · \(ByteFormat.string(result.totalBytes))",
                symbol: "checkmark.circle.fill"
            )
        }
    }

    private func failSearch(_ error: Error) {
        isSearching = false
        cancellation = nil
        progress = nil
        if case MediaSearchError.cancelled = error { return }
        reportError(error.localizedDescription)
    }

    // MARK: - Move

    public func moveSelected() {
        guard canMove, let destination else { return }
        let files = selectedFiles
        guard !files.isEmpty else { return }

        isMoving = true
        moveProgress = OperationProgress(done: 0, total: files.count)

        workQueue.async { [weak self] in
            let mover = MediaMover()
            let result = mover.move(files: files, to: destination) { done, total in
                DispatchQueue.main.async {
                    guard let self, self.isMoving else { return }
                    self.moveProgress = OperationProgress(done: done, total: total)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.finishMove(result)
            }
        }
    }

    private func finishMove(_ result: MediaMoveResult) {
        isMoving = false
        moveProgress = nil

        let movedIDs = Set(result.moved.map(\.id))
        if !movedIDs.isEmpty {
            results.removeAll { movedIDs.contains($0.id) }
            selectedIDs.subtract(movedIDs)
        }

        if !result.moved.isEmpty {
            appModel?.showToast(
                "Перенесено \(Plural.files(result.moved.count)) · \(ByteFormat.string(result.movedBytes))",
                symbol: "arrow.right.circle.fill"
            )
        }

        if let failure = result.failures.first {
            let suffix = result.failures.count > 1 ? " Ещё ошибок: \(result.failures.count - 1)." : ""
            reportError("«\(failure.name)»: \(failure.message)\(suffix)")
        }
    }

    // MARK: - Photos

    public func importSelectedToPhotos() async {
        guard canImportToPhotos else { return }
        let files = selectedPhotosFiles
        guard !files.isEmpty else { return }

        isImportingToPhotos = true
        photosProgress = OperationProgress(done: 0, total: files.count)

        do {
            let result = try await PhotosImporter().importImages(files) { [weak self] done, total in
                DispatchQueue.main.async {
                    guard let self, self.isImportingToPhotos else { return }
                    self.photosProgress = OperationProgress(done: done, total: total)
                }
            }
            finishPhotos(result)
        } catch PhotosImportError.accessDenied {
            isImportingToPhotos = false
            photosProgress = nil
            showPhotosAccessAlert = true
        } catch PhotosImportError.cancelled {
            isImportingToPhotos = false
            photosProgress = nil
        } catch {
            isImportingToPhotos = false
            photosProgress = nil
            reportError(error.localizedDescription)
        }
    }

    private func finishPhotos(_ result: PhotosImportResult) {
        isImportingToPhotos = false
        photosProgress = nil

        let importedIDs = Set(result.imported.map(\.id))
        if !importedIDs.isEmpty {
            results.removeAll { importedIDs.contains($0.id) }
            selectedIDs.subtract(importedIDs)
        }

        if !result.imported.isEmpty {
            var text = "В Фото: \(Plural.files(result.imported.count)) · \(ByteFormat.string(result.importedBytes))"
            if !result.skipped.isEmpty {
                text += " · пропущено \(result.skipped.count)"
            }
            appModel?.showToast(text, symbol: "photo.on.rectangle.angled")
        }

        if let failure = result.failures.first {
            let suffix = result.failures.count > 1 ? " Ещё ошибок: \(result.failures.count - 1)." : ""
            reportError("«\(failure.name)»: \(failure.message)\(suffix)")
        } else if result.imported.isEmpty && !result.skipped.isEmpty {
            reportError("Выбранные файлы не являются изображениями, которые поддерживает «Фото».")
        }
    }

    // MARK: - Previews

    /// Populates the tab without touching the file system. Used by the
    /// snapshot renderer and UI fixtures.
    public func loadPreview(
        sources: [URL],
        types: Set<MediaType>,
        files: [MediaFile],
        destination: URL? = nil,
        selected: Set<String> = []
    ) {
        self.sources = sources
        self.types = types
        self.results = files.sorted {
            if $0.size == $1.size { return $0.path < $1.path }
            return $0.size > $1.size
        }
        self.destination = destination
        self.selectedIDs = selected
        self.hasSearched = true
        self.isSearching = false
        self.progress = nil
        self.skippedItems = 0
        self.truncated = false
        self.searchDuration = 1.4
        self.resultFilter = ""
    }

    public func openPhotosSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Photos",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Selection

    public func selectAllFiltered() {
        selectedIDs = Set(filteredResults.map(\.id))
    }

    public func clearSelection() {
        selectedIDs = []
    }

    // MARK: - Helpers

    private func invalidateResults() {
        guard !isSearching && !isMoving && !isImportingToPhotos else { return }
        results = []
        selectedIDs = []
        hasSearched = false
        progress = nil
        skippedItems = 0
        truncated = false
        searchDuration = 0
    }

    private func reportError(_ message: String) {
        appModel?.errorMessage = message
    }
}
