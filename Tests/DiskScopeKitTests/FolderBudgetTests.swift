import Foundation
import XCTest
@testable import DiskScopeKit

final class FolderBudgetTests: XCTestCase {
    func testStatusBoundaries() {
        let budget = FolderBudget(path: "/tmp/Projects", limitBytes: 1_000)
        XCTAssertEqual(FolderBudgetStatus(budget: budget, currentBytes: 0).fraction, 0)
        XCTAssertEqual(FolderBudgetStatus(budget: budget, currentBytes: 500).fraction, 0.5, accuracy: 0.001)
        XCTAssertFalse(FolderBudgetStatus(budget: budget, currentBytes: 1_000).exceeded)
        XCTAssertEqual(FolderBudgetStatus(budget: budget, currentBytes: 1_000).fraction, 1)
        XCTAssertTrue(FolderBudgetStatus(budget: budget, currentBytes: 1_001).exceeded)
        XCTAssertEqual(FolderBudgetStatus(budget: budget, currentBytes: 1_001).overBy, 1)
        XCTAssertEqual(FolderBudgetStatus(budget: budget, currentBytes: 400).remainingBytes, 600)
        XCTAssertNil(FolderBudgetEvaluator.status(currentBytes: 500, limitBytes: 0, path: "/tmp"))
    }

    func testStoreRoundTripAndRemoval() throws {
        let suite = "DiskScopeBudgetTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        FolderBudgetStore.upsert(path: "/tmp/B", limitBytes: 2_000, defaults: defaults)
        FolderBudgetStore.upsert(path: "/tmp/A/", limitBytes: 1_000, defaults: defaults)
        let loaded = FolderBudgetStore.load(defaults: defaults)
        XCTAssertEqual(loaded.map(\.path), ["/tmp/A", "/tmp/B"])
        XCTAssertEqual(loaded.map(\.limitBytes), [1_000, 2_000])

        FolderBudgetStore.upsert(path: "/tmp/A", limitBytes: 3_000, defaults: defaults)
        XCTAssertEqual(FolderBudgetStore.load(defaults: defaults).first?.limitBytes, 3_000)

        FolderBudgetStore.remove(path: "/tmp/A", defaults: defaults)
        XCTAssertEqual(FolderBudgetStore.load(defaults: defaults).map(\.path), ["/tmp/B"])
    }

    func testMatchingPath() {
        let budgets = [
            FolderBudget(path: "/tmp/A", limitBytes: 10),
            FolderBudget(path: "/tmp/B", limitBytes: 20),
        ]
        XCTAssertEqual(FolderBudgetEvaluator.matching(path: "/tmp/A/", in: budgets)?.limitBytes, 10)
        XCTAssertNil(FolderBudgetEvaluator.matching(path: "/tmp/C", in: budgets))
    }

    func testNotifierFiresOnceUntilRecovered() throws {
        let suite = "DiskScopeBudgetNotify-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let budget = FolderBudget(path: "/tmp/A", limitBytes: 1_000)
        let over = FolderBudgetStatus(budget: budget, currentBytes: 1_500)
        let under = FolderBudgetStatus(budget: budget, currentBytes: 500)

        XCTAssertEqual(FolderBudgetNotifier.newlyExceeded([over], defaults: defaults).count, 1)
        XCTAssertEqual(FolderBudgetNotifier.newlyExceeded([over], defaults: defaults).count, 0)
        XCTAssertEqual(FolderBudgetNotifier.newlyExceeded([under], defaults: defaults).count, 0)
        XCTAssertEqual(FolderBudgetNotifier.newlyExceeded([over], defaults: defaults).count, 1)
    }
}
