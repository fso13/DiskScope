import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class HistoryModelTests: XCTestCase {
    func testRecordReloadDeleteAndClear() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeHistoryModel-\(UUID().uuidString)", isDirectory: true)
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeHistory-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: historyURL)
        }
        try Data(repeating: 0x41, count: 1_000).write(to: root.appendingPathComponent("a.bin"))
        let tree = try DiskScanner(options: .detailed).scan(path: root.path)

        let model = HistoryModel(store: ScanHistoryStore(url: historyURL))
        model.attach { tree }
        model.record(tree)
        model.record(tree)
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertEqual(model.entries.first?.rootPath, tree.rootPath)
        XCTAssertNotNil(model.diff(for: model.entries[0]).totalAfter)

        model.reload()
        XCTAssertEqual(model.entries.count, 2)
        let first = model.entries[0]
        model.delete(first)
        XCTAssertEqual(model.entries.count, 1)
        model.clear()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(ScanHistoryStore(url: historyURL).load().isEmpty)
    }
}
