import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class NavigationModelTests: XCTestCase {
    private func tree() throws -> ScanTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeNav-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 10_000).write(to: root.appendingPathComponent("Sub/a.bin"))
        try Data(repeating: 0x42, count: 20_000).write(to: root.appendingPathComponent("b.bin"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try DiskScanner(options: .detailed).scan(path: root.path)
    }

    func testNavigateAndRebuild() throws {
        let tree = try tree()
        let nav = NavigationModel()
        nav.attach { tree }
        nav.rebuild()
        XCTAssertEqual(nav.rows.map(\.name).sorted(), ["Sub", "b.bin"])

        let sub = try XCTUnwrap(nav.rows.first { $0.name == "Sub" })
        nav.navigate(to: sub.id)
        XCTAssertEqual(nav.currentIndex, sub.id)
        XCTAssertEqual(nav.rows.map(\.name), ["a.bin"])
        nav.goUp()
        XCTAssertEqual(nav.currentIndex, 0)
    }

    func testSearchAndReset() throws {
        let tree = try tree()
        let nav = NavigationModel()
        nav.attach { tree }
        nav.searchText = "b.bin"
        XCTAssertEqual(nav.rows.map(\.name), ["b.bin"])
        nav.reset()
        XCTAssertEqual(nav.currentIndex, 0)
        XCTAssertTrue(nav.rows.isEmpty)
    }
}
