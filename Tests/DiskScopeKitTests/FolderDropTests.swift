import Foundation
import XCTest
@testable import DiskScopeKit

final class FolderDropTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sub"),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: root.appendingPathComponent("file.txt"))
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testDirectoryIsUsedAsIs() {
        let url = FolderDrop.folderURL(for: root.appendingPathComponent("Sub"))
        XCTAssertEqual(url?.standardizedFileURL, root.appendingPathComponent("Sub").standardizedFileURL)
    }

    func testFileUsesParentFolder() {
        let url = FolderDrop.folderURL(for: root.appendingPathComponent("file.txt"))
        XCTAssertEqual(url?.standardizedFileURL, root.standardizedFileURL)
    }

    func testMissingPathReturnsNil() {
        XCTAssertNil(FolderDrop.folderURL(for: root.appendingPathComponent("missing")))
    }
}
