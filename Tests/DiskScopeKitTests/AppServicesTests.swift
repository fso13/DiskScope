import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class AppServicesTests: XCTestCase {
    func testInjectedHistoryAndCacheAreUsed() throws {
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeServicesHistory-\(UUID().uuidString).json")
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeServicesCache-\(UUID().uuidString).plist")
        defer {
            try? FileManager.default.removeItem(at: historyURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }
        let entry = ScanHistoryEntry(
            date: Date(), rootPath: "/tmp/root", rootName: "root",
            totalSize: 42, fileCount: 1, folderCount: 1, folderSizes: ["A": 42]
        )
        let historyStore = ScanHistoryStore(url: historyURL)
        historyStore.save([entry])
        let cache = ScanTreeCache(url: cacheURL)
        let services = AppServices(cache: cache, historyStore: historyStore)

        let model = AppModel(services: services)
        XCTAssertEqual(model.history.entries.map(\.rootName), ["root"])
        let controller = ScanController(cache: cache)
        XCTAssertEqual(controller.cacheDirectory, cacheURL.deletingLastPathComponent().path)
    }
}
