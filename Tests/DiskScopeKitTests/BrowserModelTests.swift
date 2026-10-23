import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class BrowserModelTests: XCTestCase {
    private func makeTree() throws -> ScanTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeBrowser-\(UUID().uuidString)", isDirectory: true)
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

    func testPresentationFollowsNavigation() throws {
        let tree = try makeTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        XCTAssertEqual(model.browser.currentName, model.browser.rootDisplayName)
        XCTAssertEqual(model.browser.breadcrumbs, [0])
        XCTAssertFalse(model.browser.canGoUp)
        XCTAssertEqual(model.browser.currentPath, tree.path(of: 0))
        XCTAssertEqual(model.browser.currentSize, tree.node(0).size)
        XCTAssertEqual(model.browser.currentItemCount, Int(tree.node(0).itemCount))
        XCTAssertEqual(model.browser.currentDirectCount, tree.children(of: 0).count)

        let folder = try XCTUnwrap(model.currentRows.first { $0.isContainer })
        model.navigate(to: folder.id)
        XCTAssertEqual(model.browser.currentName, "Sub")
        XCTAssertEqual(model.browser.breadcrumbs, [0, folder.id])
        XCTAssertTrue(model.browser.canGoUp)
        XCTAssertEqual(model.browser.currentDirectCount, 1)
    }

    func testSelectionSummaryAndRevealAvailability() throws {
        let tree = try makeTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        XCTAssertEqual(model.browser.selectedCount, 0)
        XCTAssertEqual(model.browser.selectedSize, 0)
        XCTAssertFalse(model.browser.canRevealSelection)

        let file = try XCTUnwrap(model.currentRows.first { !$0.isContainer && !$0.isAggregate })
        model.selection = [file.id]
        XCTAssertEqual(model.browser.selectedCount, 1)
        XCTAssertEqual(model.browser.selectedSize, file.size)
        XCTAssertTrue(model.browser.canRevealSelection)
    }

    func testFolderActivationAndOpeningNavigate() throws {
        let tree = try makeTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        let folder = try XCTUnwrap(model.currentRows.first { $0.isContainer })
        model.browser.activateRow(folder.id)
        XCTAssertEqual(model.currentIndex, folder.id)

        model.browser.openRow(0)
        XCTAssertEqual(model.currentIndex, 0)
        model.browser.openRow(folder.id)
        XCTAssertEqual(model.currentIndex, folder.id)
    }

    func testVolumesAndRootNames() throws {
        let tree = try makeTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        XCTAssertEqual(model.browser.rootDisplayName, URL(fileURLWithPath: tree.rootPath).lastPathComponent)
        XCTAssertFalse(model.browser.homePath.isEmpty)
        XCTAssertNotNil(model.browser.internalVolume)
        XCTAssertNotNil(model.browser.volume)
        XCTAssertFalse(model.browser.freeSpaceText.isEmpty)
        XCTAssertFalse(model.browser.hasPermissionIssues)

        model.browser.refreshVolumes()
        XCTAssertFalse(model.volumes.isEmpty)
    }
}
