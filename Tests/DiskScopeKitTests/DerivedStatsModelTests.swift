import Combine
import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class DerivedStatsModelTests: XCTestCase {
    private func makeTree() throws -> ScanTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeDerivedStats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sub"),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 5_000)
            .write(to: root.appendingPathComponent("video.mov"))
        try Data(repeating: 0x42, count: 3_000)
            .write(to: root.appendingPathComponent("Sub/notes.txt"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try DiskScanner(options: .detailed).scan(path: root.path)
    }

    func testApplyPopulatesRowsAndStats() throws {
        let tree = try makeTree()
        let model = DerivedStatsModel()
        model.attach(treeProvider: { tree }, categoryProvider: { nil }, searchProvider: { "" })

        model.apply(tree: tree)

        XCTAssertFalse(model.largestItems.isEmpty)
        XCTAssertFalse(model.categoryStats.isEmpty)
        XCTAssertEqual(model.filteredLargestRows.count, model.largestItems.count)
    }

    func testFilteredRowsUseCategoryAndSearch() throws {
        let tree = try makeTree()
        var category: FileCategory?
        var search = ""
        let model = DerivedStatsModel()
        model.attach(
            treeProvider: { tree },
            categoryProvider: { category },
            searchProvider: { search }
        )
        model.apply(tree: tree)

        search = "video"
        XCTAssertEqual(model.filteredLargestRows.map(\.name), ["video.mov"])

        search = ""
        category = .video
        XCTAssertEqual(model.filteredLargestRows.map(\.name), ["video.mov"])

        category = nil
        search = "notes"
        XCTAssertEqual(model.filteredLargestRows.map(\.name), ["notes.txt"])
    }

    func testRefreshPopulatesAsyncAndResetClears() async throws {
        let tree = try makeTree()
        let model = DerivedStatsModel()
        model.attach(treeProvider: { tree }, categoryProvider: { nil }, searchProvider: { "" })

        let loaded = expectation(description: "stats loaded")
        var cancellables = Set<AnyCancellable>()
        model.$largestItems
            .dropFirst()
            .sink { rows in
                if !rows.isEmpty { loaded.fulfill() }
            }
            .store(in: &cancellables)

        model.refresh()
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertFalse(model.categoryStats.isEmpty)

        model.reset()
        XCTAssertTrue(model.largestItems.isEmpty)
        XCTAssertTrue(model.categoryStats.isEmpty)
    }
}
