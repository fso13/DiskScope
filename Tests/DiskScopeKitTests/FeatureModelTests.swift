import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class FeatureModelTests: XCTestCase {
    func testDiskModelPreview() {
        let volume = VolumeInfo(
            id: "/", name: "Test", path: "/", totalBytes: 100,
            freeBytes: 40, importantFreeBytes: 50, isInternal: true, isRemovable: false
        )
        let overview = DiskOverview(
            volume: volume, purgeableBytes: 10, trash: .empty(url: URL(fileURLWithPath: "/tmp/.Trash")),
            snapshots: [], updatedAt: Date()
        )
        let model = DiskModel()
        model.preview(overview)
        XCTAssertEqual(model.overview?.volume.name, "Test")
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.error)
    }

    func testBudgetModelReportsLimitStatus() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeBudgetModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            FolderBudgetStore.remove(path: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try Data(repeating: 0x41, count: 2_000_000).write(to: root.appendingPathComponent("data.bin"))
        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        let model = BudgetModel()
        model.attach(treeProvider: { tree }, historyProvider: { [] })
        model.set(path: root.path, limitBytes: 1_000)
        let status = try XCTUnwrap(model.status(forPath: root.path))
        XCTAssertTrue(status.exceeded)
        XCTAssertGreaterThan(status.overBy, 0)
        model.remove(path: root.path)
        XCTAssertNil(model.status(forPath: root.path))
    }
}
