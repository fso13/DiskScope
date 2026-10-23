import Combine
import Foundation

/// Owns scan phase, tree, progress and the background scan queue.
@MainActor
public final class ScanController: ObservableObject {
    @Published public internal(set) var phase: AppModel.Phase = .welcome
    @Published public internal(set) var tree: ScanTree?
    @Published public internal(set) var progress: ScanProgress?
    @Published public internal(set) var lastScanPath: String? = UserDefaults.standard.string(forKey: "lastScanPath")

    private var cancellation: ScanCancellation?
    private var activeScanID = UUID()
    private let queue = DispatchQueue(label: "ru.diskscope.scan", qos: .userInitiated)
    private let cache: ScanTreeCache
    private let makeScanner: (ScanOptions) -> DiskScanner

    public init(
        cache: ScanTreeCache = .shared,
        scannerFactory: @escaping (ScanOptions) -> DiskScanner = { DiskScanner(options: $0) }
    ) {
        self.cache = cache
        self.makeScanner = scannerFactory
    }

    var cacheDirectory: String {
        cache.fileURL.deletingLastPathComponent().path
    }

    func start(
        path: String,
        options: ScanOptions,
        onResult: @escaping @MainActor (ScanTree, Bool) -> Void,
        onFailure: @escaping @MainActor (Error, Bool) -> Void
    ) {
        cancellation?.cancel()
        let token = ScanCancellation()
        cancellation = token
        activeScanID = UUID()
        let scanID = activeScanID
        phase = .scanning
        progress = ScanProgress(currentPath: path)
        lastScanPath = path
        UserDefaults.standard.set(path, forKey: "lastScanPath")

        queue.async { [weak self] in
            guard let self else { return }
            if let cached = self.cache.reusableTree(rootPath: path, options: options) {
                DispatchQueue.main.async {
                    guard self.activeScanID == scanID else { return }
                    self.progress = nil
                    onResult(cached, true)
                }
                return
            }

            let scanner = makeScanner(options)
            do {
                let result = try scanner.scan(path: path, cancellation: token, progress: { update in
                    DispatchQueue.main.async {
                        guard self.activeScanID == scanID else { return }
                        self.progress = update
                    }
                })
                let eventID = FSEventsHistory.currentEventID()
                DispatchQueue.global(qos: .utility).async {
                    self.cache.save(tree: result, options: options, eventID: eventID)
                }
                DispatchQueue.main.async {
                    guard self.activeScanID == scanID else { return }
                    self.progress = nil
                    onResult(result, false)
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.activeScanID == scanID else { return }
                    onFailure(error, token.isCancelled)
                }
            }
        }
    }

    func finish(_ tree: ScanTree) {
        self.tree = tree
        phase = .ready
        progress = nil
    }

    func fail(_ error: Error) {
        progress = nil
        phase = .failed(error.localizedDescription)
    }

    func cancel() {
        cancellation?.cancel()
        cancellation = nil
        activeScanID = UUID()
        progress = nil
        phase = tree == nil ? .welcome : .ready
    }

    func invalidate() {
        activeScanID = UUID()
        cancellation?.cancel()
    }

    func previewScanning(path: String, progress: ScanProgress) {
        tree = nil
        phase = .scanning
        self.progress = progress
        lastScanPath = path
    }

    func previewWelcome() {
        tree = nil
        phase = .welcome
        progress = nil
    }
}
