import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class CleanupModelTests: XCTestCase {
    private func suggestion(_ id: String, size: Int64, risk: CleanupRisk, disposition: CleanupDisposition = .trash) -> CleanupSuggestion {
        CleanupSuggestion(
            id: id,
            ruleID: risk == .safe ? "cache" : "review",
            title: id,
            nodeIndex: 1,
            name: id,
            path: "/tmp/\(id)",
            relativePath: id,
            size: size,
            itemCount: 1,
            risk: risk,
            reason: "test",
            isDirectory: true,
            disposition: disposition,
            isSelectedByDefault: risk == .safe
        )
    }

    func testSelectionTotalsAndPermanentWarning() {
        let model = CleanupModel()
        model.suggestions = [
            suggestion("safe", size: 100, risk: .safe),
            suggestion("review", size: 200, risk: .review),
            suggestion("trash", size: 300, risk: .expert, disposition: .deletePermanently),
        ]
        model.selectDefaults()
        XCTAssertEqual(model.selectedSize, 100)
        XCTAssertTrue(model.canApply)
        XCTAssertFalse(model.hasPermanentSelection)

        model.select([model.suggestions[2]])
        XCTAssertEqual(model.selectedCount, 2)
        XCTAssertEqual(model.totalSize, 600)
        XCTAssertTrue(model.hasPermanentSelection)
        XCTAssertTrue(model.confirmationMessage.contains("безвозвратно"))

        model.clearSelection()
        XCTAssertFalse(model.canApply)
    }

    func testResetClearsEverything() {
        let model = CleanupModel()
        model.suggestions = [suggestion("safe", size: 100, risk: .safe)]
        model.selection = ["safe"]
        model.reset()
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertFalse(model.loading)
    }
}
