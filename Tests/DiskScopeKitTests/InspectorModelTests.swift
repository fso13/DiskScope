import AppKit
import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class InspectorModelTests: XCTestCase {
    private func makeTree() throws -> ScanTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeInspector-\(UUID().uuidString)", isDirectory: true)
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

    private func index(of name: String, in tree: ScanTree) throws -> Int32 {
        try XCTUnwrap(tree.children(of: 0).first { tree.name(of: $0) == name })
    }

    func testInspectorTargetFollowsSelectionAndCurrentFolder() throws {
        let tree = try makeTree()
        let file = try index(of: "video.mov", in: tree)
        let folder = try index(of: "Sub", in: tree)
        var selection: Set<Int32> = []
        var currentIndex: Int32 = 0
        let inspector = InspectorModel()
        inspector.attach(
            treeProvider: { tree },
            currentIndexProvider: { currentIndex },
            selectionProvider: { selection },
            toast: { _, _ in },
            error: { _ in }
        )

        XCTAssertEqual(inspector.inspectorNode, 0)
        XCTAssertFalse(inspector.canQuickLook)

        selection = [file]
        XCTAssertEqual(inspector.inspectorNode, file)
        XCTAssertTrue(inspector.canQuickLook)

        selection = [folder]
        XCTAssertEqual(inspector.inspectorNode, folder)
        XCTAssertFalse(inspector.canQuickLook)

        selection = [file, folder]
        XCTAssertNil(inspector.inspectorNode)
        XCTAssertTrue(inspector.canQuickLook)

        selection = []
        currentIndex = folder
        XCTAssertEqual(inspector.inspectorNode, folder)
    }

    func testQuickLookPrefersSelectedFileAndClearsForFolder() throws {
        let tree = try makeTree()
        let file = try index(of: "video.mov", in: tree)
        let folder = try index(of: "Sub", in: tree)
        var selection: Set<Int32> = []
        let inspector = InspectorModel()
        inspector.attach(
            treeProvider: { tree },
            currentIndexProvider: { 0 },
            selectionProvider: { selection },
            toast: { _, _ in },
            error: { _ in }
        )

        inspector.previewSelection()
        XCTAssertNil(inspector.quickLookURL)

        selection = [file]
        inspector.previewSelection()
        XCTAssertEqual(inspector.quickLookURL, tree.url(of: file))

        selection = [folder]
        inspector.previewSelection()
        XCTAssertNil(inspector.quickLookURL)

        inspector.previewNode(file)
        XCTAssertEqual(inspector.quickLookURL, tree.url(of: file))
    }

    func testMetadataLoadsForFileAndResetsForRoot() throws {
        let tree = try makeTree()
        let file = try index(of: "video.mov", in: tree)
        let inspector = InspectorModel()
        inspector.attach(
            treeProvider: { tree },
            currentIndexProvider: { 0 },
            selectionProvider: { [] },
            toast: { _, _ in },
            error: { _ in }
        )

        inspector.loadMetadata(for: file)
        let metadata = try XCTUnwrap(inspector.metadata(for: file))
        XCTAssertEqual(metadata.logicalSize, 5_000)
        XCTAssertFalse(metadata.isPackage)
        XCTAssertNotNil(metadata.created)
        XCTAssertNotNil(metadata.modified)

        inspector.loadMetadata(for: 0)
        XCTAssertNil(inspector.metadata)
        XCTAssertNil(inspector.metadataIndex)
        XCTAssertNil(inspector.metadata(for: file))
    }

    func testCopyPathsWritesPasteboardAndReportsToast() throws {
        let tree = try makeTree()
        let file = try index(of: "video.mov", in: tree)
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        addTeardownBlock {
            pasteboard.clearContents()
            if let previous { pasteboard.setString(previous, forType: .string) }
        }

        var toasts: [(text: String, symbol: String)] = []
        let inspector = InspectorModel()
        inspector.attach(
            treeProvider: { tree },
            currentIndexProvider: { 0 },
            selectionProvider: { [] },
            toast: { toasts.append((text: $0, symbol: $1)) },
            error: { _ in }
        )

        inspector.copyPaths([file])

        XCTAssertEqual(pasteboard.string(forType: .string), tree.path(of: file))
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(toasts.first?.text, "Путь скопирован")
        XCTAssertEqual(toasts.first?.symbol, "doc.on.doc")
    }
}
