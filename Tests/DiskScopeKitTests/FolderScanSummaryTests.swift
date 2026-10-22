import Foundation
import XCTest
@testable import DiskScopeKit

final class FolderScanSummaryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeIntent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 256 * 1024).write(to: root.appendingPathComponent("data.bin"))
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testSummaryFromFolder() throws {
        let summary = try FolderScanSummary.scan(url: root)
        XCTAssertEqual(summary.path, root.path)
        XCTAssertEqual(summary.name, root.lastPathComponent)
        XCTAssertGreaterThan(summary.totalBytes, 0)
        XCTAssertEqual(summary.files, 1)
        XCTAssertFalse(summary.totalHuman.isEmpty)
        XCTAssertEqual(summary.hardLinkBytes, 0)
    }

    func testRejectsAFile() throws {
        let file = root.appendingPathComponent("data.bin")
        XCTAssertThrowsError(try FolderScanSummary.scan(url: file)) { error in
            guard case ScanError.notDirectory = error else {
                return XCTFail("expected notDirectory, got \(error)")
            }
        }
    }
}
