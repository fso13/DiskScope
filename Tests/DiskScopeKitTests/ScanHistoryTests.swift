import Foundation
import XCTest
@testable import DiskScopeKit

final class ScanHistoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeHistory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("Sub/one.bin", bytes: 1_000_000)
        try write("Sub/two.bin", bytes: 2_000_000)
        try write("Reports/a.txt", bytes: 10_000)
        try write("root.txt", bytes: 1_000)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func write(_ relative: String, bytes: Int) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    private func scan() throws -> ScanTree {
        try DiskScanner(options: .detailed).scan(path: root.path)
    }

    func testEntryCapturesTotalsAndTopLevelFolders() throws {
        let tree = try scan()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = ScanHistoryEntry.make(tree: tree, date: date)

        XCTAssertEqual(entry.rootPath, tree.rootPath)
        XCTAssertEqual(entry.date, date)
        XCTAssertEqual(entry.totalSize, tree.totalSize)
        XCTAssertEqual(entry.fileCount, tree.totalFiles)
        XCTAssertEqual(Set(entry.folderSizes.keys), Set(["Sub", "Reports"]))
        XCTAssertGreaterThan(entry.folderSizes["Sub"] ?? 0, entry.folderSizes["Reports"] ?? 0)
    }

    func testDiffShowsGrowthAndNewFolders() throws {
        let oldTree = try scan()
        let entry = ScanHistoryEntry.make(tree: oldTree, date: Date(timeIntervalSince1970: 1_800_000_000))

        try write("Sub/three.bin", bytes: 3_000_000)
        try write("New/thing.bin", bytes: 4_000_000)
        let newTree = try scan()
        let diff = ScanHistoryDiff.make(entry: entry, tree: newTree)

        XCTAssertTrue(diff.hasCurrent)
        XCTAssertTrue(diff.comparable)
        XCTAssertGreaterThan(diff.totalDelta ?? 0, 0)
        XCTAssertGreaterThan(diff.fileCountDelta ?? 0, 0)
        XCTAssertEqual(diff.changes.first?.path, "New")
        XCTAssertEqual(diff.changes.first?.before, 0)
        XCTAssertGreaterThan(diff.changes.first?.after ?? 0, 0)
        XCTAssertGreaterThan(
            diff.changes.first(where: { $0.path == "Sub" })?.delta ?? 0,
            0
        )
    }

    func testDiffRejectsADifferentRootAndMissingTree() throws {
        let entry = ScanHistoryEntry.make(tree: try scan())
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeOther-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: other) }
        try Data(repeating: 0x42, count: 100).write(to: other.appendingPathComponent("x.txt"))

        let otherTree = try DiskScanner(options: .detailed).scan(path: other.path)
        XCTAssertFalse(ScanHistoryDiff.make(entry: entry, tree: otherTree).comparable)

        let missing = ScanHistoryDiff.make(entry: entry, tree: nil)
        XCTAssertFalse(missing.hasCurrent)
        XCTAssertNil(missing.totalAfter)
        XCTAssertNil(missing.totalDelta)
    }

    func testStoreRoundTripAndClear() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeHistory-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ScanHistoryStore(url: url)
        let entry = ScanHistoryEntry(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            rootPath: "/tmp/Test",
            rootName: "Test",
            totalSize: 42,
            fileCount: 3,
            folderCount: 1,
            folderSizes: ["Sub": 10]
        )

        store.save([entry])
        XCTAssertEqual(store.load(), [entry])
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testCorruptStoreLoadsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeHistory-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(ScanHistoryStore(url: url).load().isEmpty)
    }
}
