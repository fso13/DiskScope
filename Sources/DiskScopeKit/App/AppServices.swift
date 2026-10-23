import Foundation

/// Injectable dependencies for the feature models.
public struct AppServices {
    public let cache: ScanTreeCache
    public let historyStore: ScanHistoryStore
    public let scannerFactory: (ScanOptions) -> DiskScanner

    public init(
        cache: ScanTreeCache = .shared,
        historyStore: ScanHistoryStore = ScanHistoryStore(),
        scannerFactory: @escaping (ScanOptions) -> DiskScanner = { DiskScanner(options: $0) }
    ) {
        self.cache = cache
        self.historyStore = historyStore
        self.scannerFactory = scannerFactory
    }

    public static let live = AppServices()
}
