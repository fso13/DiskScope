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

    private func cleanupSuggestion(
        id: String,
        size: Int64,
        risk: CleanupRisk = .safe,
        permanent: Bool = false,
        selected: Bool = true
    ) -> CleanupSuggestion {
        CleanupSuggestion(
            id: id,
            ruleID: id,
            title: id,
            nodeIndex: 1,
            name: id,
            path: "/tmp/\(id)",
            relativePath: id,
            size: size,
            itemCount: 1,
            risk: risk,
            reason: "reason",
            isDirectory: false,
            disposition: permanent ? .deletePermanently : .trash,
            isSelectedByDefault: selected
        )
    }

    func testScanCompletesAndPopulatesState() async throws {
        let model = AppModel()
        let ready = expectation(description: "scan finished")
        var bag = Set<AnyCancellable>()
        let derived = expectation(description: "derived stats finished")
        model.scan.$phase
            .dropFirst()
            .sink { phase in
                if phase == .ready { ready.fulfill() }
            }
            .store(in: &bag)
        model.stats.$largestItems
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
        XCTAssertFalse(model.stats.largestItems.isEmpty)
        XCTAssertFalse(model.stats.categoryStats.isEmpty)
        XCTAssertEqual(model.currentIndex, 0)

        let sub = try XCTUnwrap(model.currentRows.first { $0.name == "Sub" })
        XCTAssertTrue(sub.isContainer)
        model.navigate(to: sub.id)
        XCTAssertEqual(model.currentIndex, sub.id)
        XCTAssertEqual(model.browser.currentName, "Sub")
        XCTAssertTrue(model.browser.canGoUp)

        model.goUp()
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertFalse(model.browser.canGoUp)
    }

    func testPreviewCategoryFilterAndLargestRows() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.tree?.rootPath, scratch.path)
        XCTAssertFalse(model.stats.largestItems.isEmpty)

        model.showFiles(of: .video)
        XCTAssertEqual(model.tab, .largest)
        XCTAssertEqual(model.categoryFilter, .video)
        XCTAssertFalse(model.stats.filteredLargestRows.isEmpty)
        XCTAssertTrue(model.stats.filteredLargestRows.allSatisfy { $0.category == .video })

        model.clearCategoryFilter()
        XCTAssertNil(model.categoryFilter)
        XCTAssertGreaterThanOrEqual(model.stats.filteredLargestRows.count, 1)
    }

    func testAggregatesCannotBeTrashed() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        let aggregate = try XCTUnwrap(model.currentRows.first { $0.isAggregate })
        model.selection = [aggregate.id]
        XCTAssertFalse(model.trashOperations.canTrashSelection)
        model.trashOperations.requestSelection()
        XCTAssertFalse(model.trash.showSelectionConfirmation)

        let file = try XCTUnwrap(model.currentRows.first { !$0.isContainer && !$0.isAggregate })
        model.selection = [file.id]
        XCTAssertTrue(model.trashOperations.canTrashSelection)
        model.trashOperations.requestSelection()
        XCTAssertTrue(model.trash.showSelectionConfirmation)
        model.trash.showSelectionConfirmation = false
    }

    func testUndoIsUnavailableWithoutDeletion() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        XCTAssertFalse(model.trash.canUndo)
        model.trashOperations.undoLast()
        XCTAssertFalse(model.trash.canUndo)
    }

    func testCleanupPreviewSelectionAndTotals() throws {
        let model = AppModel()
        model.preview.load(tree: try scannedTree())
        let safe = cleanupSuggestion(id: "safe", size: 100)
        let review = cleanupSuggestion(id: "review", size: 200, risk: .review, selected: false)
        let trash = cleanupSuggestion(id: "trash", size: 300, permanent: true, selected: false)
        model.preview.cleanup([safe, review, trash])

        XCTAssertEqual(model.cleanup.totalSize, 600)
        XCTAssertEqual(model.cleanup.selectedCount, 1)
        XCTAssertEqual(model.cleanup.selectedSize, 100)
        XCTAssertTrue(model.cleanup.canApply)
        XCTAssertFalse(model.cleanup.hasPermanentSelection)

        model.cleanup.toggle("trash")
        XCTAssertTrue(model.cleanup.hasPermanentSelection)
        XCTAssertTrue(model.cleanup.confirmationMessage.contains("безвозвратно"))

        model.cleanup.clearSelection()
        XCTAssertFalse(model.cleanup.canApply)
        model.cleanup.selectDefaults()
        XCTAssertEqual(model.cleanup.selection, Set(["safe"]))
        model.cleanup.select([review, trash])
        XCTAssertEqual(model.cleanup.selection, Set(["safe", "review", "trash"]))
        XCTAssertEqual(model.cleanup.selectedSize, 600)
    }

    func testCollectionAcrossFoldersDedupesNestedAndClears() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        let sub = try XCTUnwrap(model.currentRows.first { $0.name == "Sub" })
        let video = try XCTUnwrap(model.currentRows.first { $0.name == "video.mov" })

        model.addToCollection([sub.id])
        let subSize = model.collectionSize
        XCTAssertEqual(model.collectionCount, 1)
        XCTAssertTrue(model.trashOperations.canTrashCollection)
        XCTAssertTrue(model.collectionTrashMessage.contains("⌘Z"))

        model.navigate(to: sub.id)
        let large = try XCTUnwrap(model.currentRows.first { $0.name == "large.bin" })
        model.addToCollection([large.id])
        XCTAssertEqual(model.collectionCount, 1, "Nested item must not duplicate its parent")
        XCTAssertEqual(model.collectionSize, subSize)

        model.goUp()
        model.addToCollection([video.id])
        XCTAssertEqual(model.collectionCount, 2)
        XCTAssertEqual(model.collectionSize, subSize + video.size)
        XCTAssertEqual(model.collectionRows.count, 2)
        XCTAssertTrue(model.collectionRows.contains { $0.id == video.id })

        model.toggleCollection([video.id])
        XCTAssertFalse(model.isInCollection(video.id))
        XCTAssertEqual(model.collectionCount, 1)

        model.clearCollection()
        XCTAssertFalse(model.trashOperations.canTrashCollection)

        model.addToCollection([video.id])
        model.preview.load(tree: tree)
        XCTAssertEqual(model.collectionCount, 0, "A new preview must reset the collection")
    }

    func testCollectionRejectsAggregates() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        let aggregate = try XCTUnwrap(model.currentRows.first { $0.isAggregate })
        model.addToCollection([aggregate.id])
        XCTAssertEqual(model.collectionCount, 0)
    }

    func testSearchStateResetsOnPreview() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        model.search.text = "video"
        model.search.show = true
        XCTAssertTrue(model.search.show)

        model.preview.load(tree: tree)
        XCTAssertFalse(model.search.show)
        XCTAssertEqual(model.search.text, "")
        XCTAssertTrue(model.search.hits.isEmpty)
        XCTAssertEqual(model.search.total, 0)
        XCTAssertFalse(model.search.indexing)
        XCTAssertFalse(model.search.ready)
    }

    func testInspectorAndQuickLookTargets() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        XCTAssertEqual(model.inspectorNode, 0)
        XCTAssertFalse(model.canQuickLook)

        let video = try XCTUnwrap(model.currentRows.first { $0.name == "video.mov" })
        let sub = try XCTUnwrap(model.currentRows.first { $0.name == "Sub" })

        model.selection = [video.id]
        XCTAssertEqual(model.inspectorNode, video.id)
        XCTAssertTrue(model.canQuickLook)
        model.previewSelection()
        XCTAssertEqual(model.quickLookURL?.path, tree.url(of: video.id).path)

        model.selection = [sub.id]
        XCTAssertEqual(model.inspectorNode, sub.id)
        XCTAssertFalse(model.canQuickLook)
        model.previewSelection()
        XCTAssertNil(model.quickLookURL)

        model.selection = [video.id, sub.id]
        XCTAssertNil(model.inspectorNode)
    }

    func testSearchAndNavigationReset() throws {
        let tree = try scannedTree()
        let model = AppModel()
        model.preview.load(tree: tree)
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
        model.preview.welcome()
        XCTAssertEqual(model.phase, .welcome)
        XCTAssertNil(model.tree)

        model.preview.scanning(
            path: scratch.path,
            progress: ScanProgress(entries: 10, bytes: 1024, currentPath: scratch.path, elapsed: 1)
        )
        XCTAssertEqual(model.phase, .scanning)
        XCTAssertEqual(model.progress?.bytes, 1024)
        XCTAssertTrue(model.isScanning)
    }

    func testScanRequestIsIgnoredWhileScanning() {
        let model = AppModel()
        model.preview.scanning(
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

    func testUpdateVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.1.2", than: "1.1.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1.1", than: "1.1.1"))
        XCTAssertTrue(UpdateChecker.isNewer("1.2", than: "1.1.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1.0", than: "1.1.1"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    }
}
