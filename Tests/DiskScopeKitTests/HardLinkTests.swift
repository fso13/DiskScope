import Foundation
import XCTest
@testable import DiskScopeKit

final class HardLinkTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeHardLinks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func scan(minimumFileSize: Int64 = 0) throws -> ScanTree {
        try DiskScanner(options: ScanOptions(minimumFileSize: minimumFileSize)).scan(path: root.path)
    }

    func testHardLinkIsCountedOnce() throws {
        let original = root.appendingPathComponent("original.bin")
        let link = root.appendingPathComponent("link.bin")
        try Data(repeating: 0x41, count: 1_000_000).write(to: original)
        try FileManager.default.linkItem(at: original, to: link)

        let tree = try scan()
        let nodes = tree.children(of: 0).filter { tree.node($0).nodeKind == .file }
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(tree.totalFiles, 2)

        let originals = nodes.filter { !tree.node($0).isHardLink }
        let duplicates = nodes.filter { tree.node($0).isHardLink }
        XCTAssertEqual(originals.count, 1)
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertGreaterThan(tree.node(originals[0]).size, 0)
        XCTAssertEqual(tree.node(duplicates[0]).size, 0)
        XCTAssertEqual(tree.node(duplicates[0]).nodeKind, .file)
        XCTAssertEqual(tree.report.hardLinkBytes, tree.node(originals[0]).size)

        let totalWithLink = tree.totalSize
        try FileManager.default.removeItem(at: link)
        let single = try scan()
        XCTAssertEqual(totalWithLink, single.totalSize)
        XCTAssertEqual(single.report.hardLinkBytes, 0)
    }

    func testSmallHardLinksDoNotDoubleAggregateSize() throws {
        let original = root.appendingPathComponent("small.txt")
        let link = root.appendingPathComponent("small-link.txt")
        try Data(repeating: 0x42, count: 1_000).write(to: original)
        try FileManager.default.linkItem(at: original, to: link)

        let tree = try scan(minimumFileSize: 64 * 1024)
        XCTAssertGreaterThan(tree.report.hardLinkBytes, 0)
        let withLink = tree.totalSize
        try FileManager.default.removeItem(at: link)
        let single = try scan(minimumFileSize: 64 * 1024)
        XCTAssertEqual(withLink, single.totalSize)
    }
}
