import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class TrashOperationsModelTests: XCTestCase {
    private var previousConfirmTrash: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousConfirmTrash = UserDefaults.standard.object(forKey: AppSettingsKeys.confirmTrash)
        UserDefaults.standard.set(true, forKey: AppSettingsKeys.confirmTrash)
    }

    override func tearDownWithError() throws {
        if let previousConfirmTrash {
            UserDefaults.standard.set(previousConfirmTrash, forKey: AppSettingsKeys.confirmTrash)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.confirmTrash)
        }
        try super.tearDownWithError()
    }

    private func makeTree() throws -> ScanTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeTrashOps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sub"),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 100_000)
            .write(to: root.appendingPathComponent("big.bin"))
        try Data(repeating: 0x42, count: 100)
            .write(to: root.appendingPathComponent("small.txt"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try DiskScanner(options: ScanOptions(minimumFileSize: 64 * 1024)).scan(path: root.path)
    }

    func testSelectionAvailabilityAndConfirmation() throws {
        let tree = try makeTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        XCTAssertFalse(model.trashOperations.canTrashSelection)

        let aggregate = try XCTUnwrap(model.currentRows.first { $0.isAggregate })
        model.selection = [aggregate.id]
        XCTAssertFalse(model.trashOperations.canTrashSelection)
        model.trashOperations.requestSelection()
        XCTAssertFalse(model.trash.showSelectionConfirmation)

        let file = try XCTUnwrap(model.currentRows.first { $0.name == "big.bin" })
        model.selection = [file.id]
        XCTAssertTrue(model.trashOperations.canTrashSelection)
        model.trashOperations.requestSelection()
        XCTAssertTrue(model.trash.showSelectionConfirmation)
        model.trash.showSelectionConfirmation = false
    }

    func testCollectionConfirmationAndUndoNoOp() throws {
        let tree = try makeTree()
        let model = AppModel()
        model.preview.load(tree: tree)

        let folder = try XCTUnwrap(model.currentRows.first { $0.name == "Sub" })
        model.addToCollection([folder.id])
        XCTAssertTrue(model.trashOperations.canTrashCollection)

        model.trashOperations.requestCollection()
        XCTAssertTrue(model.trash.showCollectionConfirmation)
        model.trash.showCollectionConfirmation = false

        XCTAssertFalse(model.trash.canUndo)
        model.trashOperations.undoLast()
        XCTAssertFalse(model.trash.canUndo)
    }
}
