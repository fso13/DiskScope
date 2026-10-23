import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class SearchModelTests: XCTestCase {
    func testSearchFindsAndResets() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeSearchModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 2_000_000)
            .write(to: root.appendingPathComponent("archive-old.bin"))

        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        let model = SearchModel()
        model.attach { tree }
        model.text = "archive"
        model.show = true

        for _ in 0..<40 where model.hits.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(model.hits.map(\.name), ["archive-old.bin"])
        XCTAssertTrue(model.ready)

        model.reset()
        XCTAssertFalse(model.show)
        XCTAssertEqual(model.text, "")
        XCTAssertTrue(model.hits.isEmpty)
        XCTAssertFalse(model.ready)
    }
}
