import Foundation
import XCTest
@testable import DiskScopeKit

final class ScanTreeCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 256 * 1024).write(to: root.appendingPathComponent("data.bin"))
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func makeCache() throws -> (ScanTreeCache, URL, ScanTree) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeCache-\(UUID().uuidString).plist")
        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        return (ScanTreeCache(url: url), url, tree)
    }

    func testRoundTripPreservesTreeAndMetadata() throws {
        let (cache, url, tree) = try makeCache()
        defer { try? FileManager.default.removeItem(at: url) }
        Thread.sleep(forTimeInterval: 0.5)
        Thread.sleep(forTimeInterval: 0.5)
        let eventID = FSEventsHistory.currentEventID()
        cache.save(tree: tree, options: .detailed, eventID: eventID, appVersion: "test", build: "1")

        let entry = try XCTUnwrap(cache.load())
        XCTAssertEqual(entry.metadata.rootPath, tree.rootPath)
        XCTAssertEqual(entry.metadata.minimumFileSize, 0)
        XCTAssertEqual(entry.metadata.eventID, eventID)
        XCTAssertEqual(entry.tree.snapshot.tree().totalSize, tree.totalSize)
        XCTAssertEqual(entry.tree.snapshot.tree().totalFiles, tree.totalFiles)
    }

    func testInvariantsRejectChangedOptionsAndVersions() throws {
        let (cache, url, tree) = try makeCache()
        defer { try? FileManager.default.removeItem(at: url) }
        Thread.sleep(forTimeInterval: 0.5)
        let eventID = FSEventsHistory.currentEventID()
        cache.save(tree: tree, options: .detailed, eventID: eventID, appVersion: "test", build: "1")
        let metadata = try XCTUnwrap(cache.load()).metadata

        XCTAssertTrue(ScanTreeCache.compatible(
            metadata: metadata, rootPath: tree.rootPath, options: .detailed,
            appVersion: "test", build: "1"
        ))
        XCTAssertFalse(ScanTreeCache.compatible(
            metadata: metadata, rootPath: tree.rootPath, options: .balanced,
            appVersion: "test", build: "1"
        ))
        XCTAssertFalse(ScanTreeCache.compatible(
            metadata: metadata, rootPath: tree.rootPath, options: .detailed,
            appVersion: "2.0", build: "1"
        ))
        XCTAssertFalse(ScanTreeCache.compatible(
            metadata: metadata, rootPath: "/tmp/other", options: .detailed,
            appVersion: "test", build: "1"
        ))
    }

    func testUnchangedTreeIsReusedAndChangedTreeIsNot() throws {
        let (cache, url, tree) = try makeCache()
        defer { try? FileManager.default.removeItem(at: url) }
        cache.save(
            tree: tree, options: .detailed,
            eventID: FSEventsHistory.currentEventID(),
            appVersion: "test", build: "1"
        )

        let reused = cache.reusableTree(
            rootPath: tree.rootPath, options: .detailed,
            appVersion: "test", build: "1"
        )
        XCTAssertEqual(reused?.totalSize, tree.totalSize)

        try Data(repeating: 0x42, count: 1_000).write(to: root.appendingPathComponent("new.txt"))
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertNil(cache.reusableTree(
            rootPath: tree.rootPath, options: .detailed,
            appVersion: "test", build: "1"
        ))
    }

    func testModifiedFileInvalidatesCache() throws {
        let (cache, url, tree) = try makeCache()
        defer { try? FileManager.default.removeItem(at: url) }
        Thread.sleep(forTimeInterval: 0.5)
        cache.save(
            tree: tree, options: .detailed,
            eventID: FSEventsHistory.currentEventID(),
            appVersion: "test", build: "1"
        )
        XCTAssertNotNil(cache.reusableTree(
            rootPath: tree.rootPath, options: .detailed,
            appVersion: "test", build: "1"
        ))

        let handle = try FileHandle(forWritingTo: root.appendingPathComponent("data.bin"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0x42, count: 4_096))
        try handle.close()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertNil(cache.reusableTree(
            rootPath: tree.rootPath, options: .detailed,
            appVersion: "test", build: "1"
        ))
    }

    func testExcludedCacheDirectoryIsSkipped() throws {
        let cacheDir = root.appendingPathComponent("DiskScope", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: 1_024).write(to: cacheDir.appendingPathComponent("scan-cache.plist"))
        let tree = try DiskScanner(
            options: ScanOptions(minimumFileSize: 0, excludedPaths: [cacheDir.path])
        ).scan(path: root.path)
        XCTAssertFalse(tree.children(of: 0).contains { tree.name(of: $0) == "DiskScope" })
    }

    func testClearRemovesCache() throws {
        let (cache, url, tree) = try makeCache()
        defer { try? FileManager.default.removeItem(at: url) }
        cache.save(tree: tree, options: .detailed, eventID: 1, appVersion: "test", build: "1")
        XCTAssertNotNil(cache.load())
        cache.clear()
        XCTAssertNil(cache.load())
    }
}
