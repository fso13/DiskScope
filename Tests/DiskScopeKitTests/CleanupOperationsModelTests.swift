import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class CleanupOperationsModelTests: XCTestCase {
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

    private func suggestion(id: String = "preview", selected: Bool = true) -> CleanupSuggestion {
        CleanupSuggestion(
            id: id,
            ruleID: id,
            title: id,
            nodeIndex: 1,
            name: id,
            path: "/tmp/\(id)",
            relativePath: id,
            size: 100,
            itemCount: 1,
            risk: .safe,
            reason: "reason",
            isDirectory: false,
            disposition: .trash,
            isSelectedByDefault: selected
        )
    }

    func testRequestShowsConfirmationWhenSelectionExists() {
        let model = AppModel()
        model.preview.cleanup([suggestion()])

        model.cleanupOperations.request()

        XCTAssertTrue(model.cleanup.showConfirmation)
    }

    func testRequestDoesNothingWithoutSelection() {
        let model = AppModel()
        model.preview.cleanup([suggestion(selected: false)])

        model.cleanupOperations.request()

        XCTAssertFalse(model.cleanup.showConfirmation)
    }

    func testConfirmWithoutTreeOnlyClosesConfirmation() {
        let model = AppModel()
        model.preview.cleanup([suggestion()])
        model.cleanup.showConfirmation = true

        model.cleanupOperations.confirm()

        XCTAssertFalse(model.cleanup.showConfirmation)
        XCTAssertFalse(model.trash.busy)
        XCTAssertFalse(model.cleanup.loading)
    }
}
