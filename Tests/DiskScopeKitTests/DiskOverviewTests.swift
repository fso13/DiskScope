import Foundation
import XCTest
@testable import DiskScopeKit

final class DiskOverviewTests: XCTestCase {
    func testParseSnapshotsSkipsHeadersAndSortsNewestFirst() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2024-01-02-030405.local
        com.apple.TimeMachine.2025-06-07-080910.local
        not a snapshot
        com.apple.TimeMachine.2023-12-31-235959.local
        """

        let snapshots = DiskOverviewService.parseSnapshots(output)
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots.first?.name, "com.apple.TimeMachine.2025-06-07-080910.local")
        XCTAssertEqual(snapshots.last?.name, "com.apple.TimeMachine.2023-12-31-235959.local")
        XCTAssertNotNil(snapshots.first?.date)
    }

    func testPurgeableCapacityIsTheDifferenceFromImportantUsage() {
        let volume = VolumeInfo(
            id: "/",
            name: "Test",
            path: "/",
            totalBytes: 1_000,
            freeBytes: 200,
            importantFreeBytes: 500,
            isInternal: true,
            isRemovable: false
        )

        XCTAssertEqual(volume.purgeableBytes, 300)
        let overview = DiskOverview(
            volume: volume,
            purgeableBytes: volume.purgeableBytes,
            trash: .empty(url: URL(fileURLWithPath: "/tmp/Trash")),
            snapshots: [],
            updatedAt: Date()
        )
        XCTAssertEqual(overview.purgeableBytes, 300)
        XCTAssertEqual(overview.freeBytes, 200)
        XCTAssertEqual(overview.usedBytes, 800)
    }

    func testScanTrashCountsTopLevelEntries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeTrash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(repeating: 0x41, count: 1_000).write(to: root.appendingPathComponent("one.txt"))
        try Data(repeating: 0x42, count: 2_000).write(to: root.appendingPathComponent("two.txt"))
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: 3_000).write(to: folder.appendingPathComponent("three.txt"))

        let summary = DiskOverviewService.scanTrash(at: root)
        XCTAssertEqual(summary.items, 3)
        XCTAssertGreaterThan(summary.size, 0)
        XCTAssertEqual(summary.url.path, root.path)
    }

    func testMissingTrashIsEmpty() {
        let url = URL(fileURLWithPath: "/tmp/DiskScope-no-trash-\(UUID().uuidString)")
        let summary = DiskOverviewService.scanTrash(at: url)
        XCTAssertEqual(summary.size, 0)
        XCTAssertEqual(summary.items, 0)
    }

    func testLoadUsesInjectedSnapshots() {
        let volume = VolumeInfo(
            id: "/",
            name: "Test",
            path: "/",
            totalBytes: 10_000,
            freeBytes: 4_000,
            importantFreeBytes: 6_000,
            isInternal: true,
            isRemovable: false
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let overview = DiskOverviewService.load(
            volume: volume,
            trashURL: URL(fileURLWithPath: "/tmp/DiskScope-no-trash-\(UUID().uuidString)"),
            snapshotOutput: "com.apple.TimeMachine.2026-10-22-141500.local\n",
            now: now
        )

        XCTAssertEqual(overview.snapshots.count, 1)
        XCTAssertEqual(overview.purgeableBytes, 2_000)
        XCTAssertEqual(overview.updatedAt, now)
    }
}
