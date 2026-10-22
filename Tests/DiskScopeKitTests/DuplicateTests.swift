import Foundation
import XCTest
@testable import DiskScopeKit

final class DuplicateTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeDuplicates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("A/a.bin", data: Data(repeating: 0x41, count: 2_000_000))
        try write("B/a-copy.bin", data: Data(repeating: 0x41, count: 2_000_000))
        try write("C/a-different.bin", data: Data(repeating: 0x42, count: 2_000_000))
        try write("D/unique.bin", data: Data(repeating: 0x43, count: 1_500_000))
        try write("Small/one.txt", data: Data(repeating: 0x53, count: 1_000))
        try write("Small/two.txt", data: Data(repeating: 0x53, count: 1_000))
        try FileManager.default.linkItem(
            at: root.appendingPathComponent("A/a.bin"),
            to: root.appendingPathComponent("B/a-link.bin")
        )
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func write(_ relative: String, data: Data) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    private func tree() throws -> ScanTree {
        try DiskScanner(options: .detailed).scan(path: root.path)
    }

    func testFindsContentDuplicatesAndSkipsHardLinks() throws {
        let result = DuplicateFinder.find(tree: try tree())
        XCTAssertEqual(result.groups.count, 1)
        let group = try XCTUnwrap(result.groups.first)
        XCTAssertEqual(group.files.count, 2)
        XCTAssertEqual(Set(group.files.map(\.relativePath)), Set(["A/a.bin", "B/a-copy.bin"]))
        XCTAssertFalse(group.files.contains { $0.relativePath.contains("a-link") })
        XCTAssertGreaterThan(group.size, 2_000_000)
        XCTAssertEqual(group.wastedBytes, group.size)
        XCTAssertEqual(result.totalWasted, group.size)
        XCTAssertEqual(result.candidateCount, 3)
        XCTAssertFalse(result.truncated)
    }

    func testMinimumSizeIncludesSmallDuplicatesWhenZero() throws {
        let result = DuplicateFinder.find(
            tree: try tree(),
            options: DuplicateOptions(minimumSize: 0)
        )
        XCTAssertEqual(result.groups.count, 2)
        let small = try XCTUnwrap(result.groups.first {
            $0.files.contains { $0.relativePath == "Small/one.txt" }
        })
        XCTAssertEqual(Set(small.files.map(\.relativePath)), Set(["Small/one.txt", "Small/two.txt"]))
        XCTAssertEqual(small.wastedBytes, small.size)
        XCTAssertEqual(result.totalWasted, result.groups.reduce(0) { $0 + $1.wastedBytes })
    }

    func testProgressAndCancellation() throws {
        var lastProgress = 0.0
        let result = DuplicateFinder.find(
            tree: try tree(),
            progress: { lastProgress = $0 }
        )
        XCTAssertEqual(lastProgress, 1, accuracy: 0.001)
        XCTAssertFalse(result.cancelled)

        let cancelled = DuplicateFinder.find(
            tree: try tree(),
            isCancelled: { true }
        )
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertTrue(cancelled.groups.isEmpty)
    }
}
