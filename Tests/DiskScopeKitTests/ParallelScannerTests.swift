import Foundation
import XCTest
@testable import DiskScopeKit

final class ParallelScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeParallel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("A/one.bin", bytes: 300_000)
        try write("A/sub/two.bin", bytes: 200_000)
        try write("B/three.bin", bytes: 400_000)
        try write("C/nested/deep/four.bin", bytes: 100_000)
        try write("C/five.bin", bytes: 50_000)
        try FileManager.default.linkItem(
            at: root.appendingPathComponent("A/one.bin"),
            to: root.appendingPathComponent("B/one-link.bin")
        )
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func write(_ relative: String, bytes: Int) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    private func scan(parallel: Bool) throws -> ScanTree {
        try DiskScanner(options: ScanOptions(minimumFileSize: 0, parallelTraversal: parallel))
            .scan(path: root.path)
    }

    func testParallelMatchesSerial() throws {
        let serial = try scan(parallel: false)
        let parallel = try scan(parallel: true)

        XCTAssertEqual(parallel.totalSize, serial.totalSize)
        XCTAssertEqual(parallel.totalFiles, serial.totalFiles)
        XCTAssertEqual(parallel.directoryCount(), serial.directoryCount())
        XCTAssertEqual(parallel.report.hardLinkBytes, serial.report.hardLinkBytes)
        XCTAssertEqual(
            Set(parallel.children(of: 0).map { parallel.name(of: $0) }),
            Set(serial.children(of: 0).map { serial.name(of: $0) })
        )
        for index in parallel.children(of: 0) {
            let children = parallel.children(of: index)
            let sum = children.reduce(Int64(0)) { $0 + parallel.node($1).size }
            XCTAssertEqual(sum, parallel.node(index).size, "Sizes for \(parallel.name(of: index))")
        }
    }

    func testHardLinkAcrossTopLevelDirectoriesIsCanonical() throws {
        let tree = try scan(parallel: true)
        let files = (0..<Int32(tree.count)).filter { tree.node($0).nodeKind == .file }
        let originals = files.filter { !tree.node($0).isHardLink }
        let links = files.filter { tree.node($0).isHardLink }
        XCTAssertEqual(originals.count, 5)
        XCTAssertEqual(links.count, 1)
        XCTAssertTrue(originals.contains { tree.relativePath(of: $0) == "A/one.bin" })
        XCTAssertEqual(tree.report.hardLinkBytes, tree.node(originals[0]).size)
    }

    func testSingleSubdirectoryStillScans() throws {
        let single = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeSingle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: single) }
        try FileManager.default.createDirectory(
            at: single.appendingPathComponent("Only/Sub"),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x42, count: 10_000)
            .write(to: single.appendingPathComponent("Only/Sub/file.bin"))

        let tree = try DiskScanner(options: ScanOptions(minimumFileSize: 0, parallelTraversal: true))
            .scan(path: single.path)
        XCTAssertEqual(tree.totalFiles, 1)
        XCTAssertNotNil(tree.children(of: 0).first { tree.name(of: $0) == "Only" })
    }
}
