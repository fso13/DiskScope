import Foundation
import XCTest
@testable import DiskScopeKit

final class StaleFilesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeStale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int, old: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
        if old {
            let date = Date(timeIntervalSinceNow: -800 * 86_400)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    private func find(months: Int = 12, minimumSize: Int64 = 1_000_000) throws -> StaleResult {
        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        return StaleFiles.find(
            tree: tree,
            options: StaleOptions(months: months, minimumSize: minimumSize, now: Date())
        )
    }

    func testFindsOnlyOldEligibleFiles() throws {
        try write("old.bin", bytes: 2_000_000, old: true)
        try write("recent.bin", bytes: 2_000_000)
        try write("small-old.bin", bytes: 10_000, old: true)
        try write(".git/old.bin", bytes: 2_000_000, old: true)
        try write("Pods/old.bin", bytes: 2_000_000, old: true)
        try write("App.app/Contents/old.bin", bytes: 2_000_000, old: true)

        let result = try find()
        XCTAssertEqual(result.totalFiles, 1)
        XCTAssertEqual(result.files.map(\.relativePath), ["old.bin"])
        XCTAssertGreaterThan(result.totalBytes, 2_000_000)
        XCTAssertFalse(result.truncated)
    }

    func testMonthsAndSizeFilters() throws {
        try write("old.bin", bytes: 2_000_000, old: true)
        try write("old-large.bin", bytes: 5_000_000, old: true)
        let sixMonths = try find(months: 6, minimumSize: 1_000_000)
        XCTAssertEqual(sixMonths.totalFiles, 2)
        let large = try find(months: 12, minimumSize: 4_000_000)
        XCTAssertEqual(large.files.map(\.name), ["old-large.bin"])
    }

    func testLimitAndSorting() throws {
        for index in 0..<25 {
            try write(String(format: "old-%02d.bin", index), bytes: 1_000_000 + index * 1_000, old: true)
        }
        let result = try find(minimumSize: 1_000_000)
        XCTAssertEqual(result.totalFiles, 25)
        XCTAssertEqual(result.files.count, 20)
        XCTAssertTrue(result.truncated)
        XCTAssertGreaterThanOrEqual(result.files[0].size, result.files[1].size)
    }
}
