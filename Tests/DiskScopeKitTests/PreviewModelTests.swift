import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class PreviewModelTests: XCTestCase {
    private func makeTree() throws -> ScanTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopePreviewModel-\(UUID().uuidString)", isDirectory: true)
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

    func testLoadPreviewPopulatesState() throws {
        let tree = try makeTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.tree === tree)
        XCTAssertEqual(model.fileCount, tree.totalFiles)
        XCTAssertEqual(model.folderCount, tree.directoryCount())
        XCTAssertFalse(model.stats.largestItems.isEmpty)
        XCTAssertFalse(model.stats.categoryStats.isEmpty)
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.tab, .map)
    }

    func testScanningAndWelcomePreviewsResetNavigation() throws {
        let tree = try makeTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        let folder = try XCTUnwrap(model.currentRows.first { $0.isContainer })
        model.preview.select(index: folder.id)
        XCTAssertEqual(model.selection, [folder.id])
        model.preview.navigate(to: folder.id)
        XCTAssertEqual(model.currentIndex, folder.id)

        model.preview.scanning(
            path: "/tmp/DiskScope-preview",
            progress: ScanProgress(entries: 1, bytes: 42, currentPath: "/tmp/DiskScope-preview", elapsed: 1)
        )
        XCTAssertEqual(model.phase, .scanning)
        XCTAssertEqual(model.progress?.bytes, 42)
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertTrue(model.selection.isEmpty)

        model.preview.load(tree: tree)
        model.preview.welcome()
        XCTAssertEqual(model.phase, .welcome)
        XCTAssertNil(model.tree)
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testFeaturePreviewsDelegateToModels() {
        let model = AppModel()
        let suggestion = CleanupSuggestion(
            id: "preview",
            ruleID: "preview",
            title: "preview",
            nodeIndex: 1,
            name: "preview",
            path: "/tmp/preview",
            relativePath: "preview",
            size: 100,
            itemCount: 1,
            risk: .safe,
            reason: "reason",
            isDirectory: false,
            disposition: .trash,
            isSelectedByDefault: true
        )
        let duplicate = DuplicateGroup(
            id: "duplicates",
            size: 200,
            files: [DuplicateFile(index: 1, path: "/tmp/a", relativePath: "a", modified: nil)]
        )
        let similar = SimilarImageGroup(
            id: "similar",
            images: [SimilarImage(index: 1, path: "/tmp/a", relativePath: "a", size: 10, modified: nil)]
        )
        let volume = VolumeInfo(
            id: "/", name: "Test", path: "/", totalBytes: 100,
            freeBytes: 40, importantFreeBytes: 50, isInternal: true, isRemovable: false
        )
        let overview = DiskOverview(
            volume: volume,
            purgeableBytes: 10,
            trash: .empty(url: URL(fileURLWithPath: "/tmp/.Trash")),
            snapshots: [],
            updatedAt: Date()
        )

        model.preview.cleanup([suggestion])
        model.preview.duplicates([duplicate])
        model.preview.similar([similar])
        model.preview.diskOverview(overview)

        XCTAssertEqual(model.cleanup.suggestions.map(\.id), ["preview"])
        XCTAssertEqual(model.duplicates.groups.map(\.id), ["duplicates"])
        XCTAssertEqual(model.similar.state.groups.map(\.id), ["similar"])
        XCTAssertEqual(model.disk.overview?.volume.name, "Test")
    }
}
