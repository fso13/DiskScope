import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class TrashModelTests: XCTestCase {
    func testRecordAndPopUndo() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeTrashModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.bin")
        try Data(repeating: 0x41, count: 1_000).write(to: file)
        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        let removal = tree.removingSubtrees(at: [1])

        let model = TrashModel()
        model.record(
            removal: removal,
            trashed: [(index: 1, original: file, trashed: file)],
            collectionRoots: []
        )
        XCTAssertTrue(model.canUndo)
        XCTAssertEqual(model.popUndo()?.files.count, 1)
        XCTAssertFalse(model.canUndo)
        XCTAssertNil(model.popUndo())
    }
}
