import Foundation
import XCTest
@testable import DiskScopeKit

final class CLIReportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeCLI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 256 * 1024).write(to: root.appendingPathComponent("big.bin"))
        try Data(repeating: 0x42, count: 1_000).write(to: root.appendingPathComponent("small.txt"))
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testParsesHumanSizes() {
        XCTAssertEqual(ByteSize.parse("1024"), 1_024)
        XCTAssertEqual(ByteSize.parse("10KB"), 10_000)
        XCTAssertEqual(ByteSize.parse("1.5 GB"), 1_500_000_000)
        XCTAssertEqual(ByteSize.parse(" 2 tb "), 2_000_000_000_000)
        XCTAssertNil(ByteSize.parse("nope"))
        XCTAssertNil(ByteSize.parse("-1"))
    }

    func testReportContainsMachineFieldsAndBudget() throws {
        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        let report = CLIReport.make(tree: tree, budgetBytes: 1_000, limit: 5)
        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.path, tree.rootPath)
        XCTAssertEqual(report.totalBytes, tree.totalSize)
        XCTAssertEqual(report.files, tree.totalFiles)
        XCTAssertEqual(report.budget?.withinBudget, false)
        XCTAssertGreaterThan(report.budget?.exceededBy ?? 0, 0)
        XCTAssertFalse(report.topLevel.isEmpty)
        XCTAssertFalse(report.largest.isEmpty)

        let data = try report.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["totalBytes"] as? Int64, tree.totalSize)
        XCTAssertNotNil(object["topLevel"] as? [[String: Any]])
        XCTAssertNotNil(object["largest"] as? [[String: Any]])
        XCTAssertEqual((object["budget"] as? [String: Any])?["withinBudget"] as? Bool, false)
    }

    func testBudgetWithinLimit() throws {
        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        let report = CLIReport.make(tree: tree, budgetBytes: tree.totalSize, limit: 0)
        XCTAssertEqual(report.budget?.withinBudget, true)
        XCTAssertEqual(report.budget?.exceededBy, 0)
        XCTAssertTrue(report.topLevel.isEmpty)
        XCTAssertTrue(report.largest.isEmpty)
    }
}
