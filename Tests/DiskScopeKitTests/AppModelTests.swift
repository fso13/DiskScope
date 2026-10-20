import Combine
import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class AppModelTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try write("Sub/large.bin", bytes: 1_200_000)
        try write("video.mov", bytes: 500_000)
        try write("notes.txt", bytes: 2_000)
        try write("Sub/second.bin", bytes: 800_000)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        try super.tearDownWithError()
    }

    private func write(_ relative: String, bytes: Int) throws {
        let url = scratch.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    private func scannedTree() throws -> ScanTree {
        try DiskScanner(options: ScanOptions(minimumFileSize: 64 * 1024)).scan(path: scratch.path)
    }

    func testScanCompletesAndPopulatesState() async throws {
        let model = AppModel()
        let ready = expectation(description: "scan finished")
        var bag = Set<AnyCancellable>()
        let derived = expectation(description: "derived stats finished")
        model.$phase
            .dropFirst()
            .sink { phase in
                if phase == .ready { ready.fulfill() }
            }
            .store(in: &bag)
        model.$largestItems
            .dropFirst()
            .sink { rows in
                if !rows.isEmpty { derived.fulfill() }
            }
            .store(in: &bag)

        model.scan(path: scratch.path)
        XCTAssertEqual(model.phase, .scanning)
        await fulfillment(of: [ready, derived], timeout: 30)

        let tree = try XCTUnwrap(model.tree)
        XCTAssertEqual(tree.rootPath, scratch.path)
        XCTAssertGreaterThan(model.fileCount, 0)
        XCTAssertGreaterThan(model.folderCount, 0)
        XCTAssertFalse(model.currentRows.isEmpty)
        XCTAssertFalse(model.largestItems.isEmpty)
        XCTAssertFalse(model.categoryStats.isEmpty)
        XCTAssertEqual(model.currentIndex, 0)

        let sub = try XCTUnwrap(model.currentRows.first { $0.name == "Sub" })
        XCTAssertTrue(sub.isContainer)
        model.navigate(to: sub.id)
        XCTAssertEqual(model.currentIndex, sub.id)
        XCTAssertEqual(model.currentName, "Sub")
        XCTAssertTrue(model.canGoUp)

        model.goUp()
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertFalse(model.canGoUp)
    }

    func testPreviewCategoryFilterAndLargestRows() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.loadPreview(tree: tree)

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.tree?.rootPath, scratch.path)
        XCTAssertFalse(model.largestItems.isEmpty)

        model.showFiles(of: .video)
        XCTAssertEqual(model.tab, .largest)
        XCTAssertEqual(model.categoryFilter, .video)
        XCTAssertFalse(model.filteredLargestRows.isEmpty)
        XCTAssertTrue(model.filteredLargestRows.allSatisfy { $0.category == .video })

        model.clearCategoryFilter()
        XCTAssertNil(model.categoryFilter)
        XCTAssertGreaterThanOrEqual(model.filteredLargestRows.count, 1)
    }

    func testAggregatesCannotBeTrashed() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.loadPreview(tree: tree)

        let aggregate = try XCTUnwrap(model.currentRows.first { $0.isAggregate })
        model.selection = [aggregate.id]
        XCTAssertFalse(model.canTrashSelection)
        model.requestTrashSelection()
        XCTAssertFalse(model.showTrashConfirmation)

        let file = try XCTUnwrap(model.currentRows.first { !$0.isContainer && !$0.isAggregate })
        model.selection = [file.id]
        XCTAssertTrue(model.canTrashSelection)
        model.requestTrashSelection()
        XCTAssertTrue(model.showTrashConfirmation)
        model.showTrashConfirmation = false
    }

    func testSearchAndNavigationReset() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.loadPreview(tree: tree)
        model.searchText = "video"
        XCTAssertTrue(model.currentRows.allSatisfy { $0.name.localizedCaseInsensitiveContains("video") })
        XCTAssertEqual(model.currentRows.count, 1)

        model.searchText = ""
        let sub = try XCTUnwrap(model.currentRows.first { $0.name == "Sub" })
        model.navigate(to: sub.id)
        XCTAssertEqual(model.searchText, "")
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.currentRows.count, 2)
    }

    func testMediaTabAndSourceSeeding() {
        let model = AppModel()
        XCTAssertEqual(AppModel.Tab.media.title, "Медиа")
        XCTAssertEqual(AppModel.Tab.media.symbol, "photo.on.rectangle.angled")

        model.media.seedCurrentFolder(scratch.path)
        XCTAssertEqual(model.media.sources.count, 1)
        XCTAssertEqual(model.media.sources.first?.path, scratch.standardizedFileURL.path)

        model.media.seedCurrentFolder("/tmp")
        XCTAssertEqual(model.media.sources.count, 1)

        model.media.selectAllTypes()
        XCTAssertEqual(model.media.types, Set(MediaType.allCases))
        XCTAssertTrue(model.media.canSearch)
    }

    func testWelcomeAndScanningPreviews() {
        let model = AppModel()
        model.previewWelcome()
        XCTAssertEqual(model.phase, .welcome)
        XCTAssertNil(model.tree)

        model.previewScanning(
            path: scratch.path,
            progress: ScanProgress(entries: 10, bytes: 1024, currentPath: scratch.path, elapsed: 1)
        )
        XCTAssertEqual(model.phase, .scanning)
        XCTAssertEqual(model.progress?.bytes, 1024)
        XCTAssertTrue(model.isScanning)
    }

    func testScanRequestIsIgnoredWhileScanning() {
        let model = AppModel()
        model.previewScanning(
            path: scratch.path,
            progress: ScanProgress(entries: 10, bytes: 1024, currentPath: scratch.path, elapsed: 1)
        )

        model.scan(path: "/tmp/DiskScope-should-not-start")
        model.scanHome()
        model.rescan()

        XCTAssertEqual(model.phase, .scanning)
        XCTAssertEqual(model.progress?.currentPath, scratch.path)
        XCTAssertEqual(model.progress?.bytes, 1024)
        XCTAssertTrue(model.isScanning)
    }
}
