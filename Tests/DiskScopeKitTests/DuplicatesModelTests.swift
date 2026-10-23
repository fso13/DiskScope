import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class DuplicatesModelTests: XCTestCase {
    private func group(size: Int64, files: Int) -> DuplicateGroup {
        DuplicateGroup(
            id: "g\(size)",
            size: size,
            files: (0..<files).map { index in
                DuplicateFile(
                    index: Int32(index + 1),
                    path: "/tmp/\(size)-\(index)",
                    relativePath: "\(size)-\(index)",
                    modified: nil
                )
            }
        )
    }

    func testPreviewComputesTotals() {
        let model = DuplicatesModel()
        model.preview([group(size: 1_000, files: 2), group(size: 2_000, files: 3)])
        XCTAssertEqual(model.groups.count, 2)
        XCTAssertEqual(model.totalWasted, 1_000 + 4_000)
        XCTAssertEqual(model.candidateCount, 5)
        XCTAssertEqual(model.progress, 1)
        XCTAssertFalse(model.scanning)
    }

    func testMinimumSizeResetsResults() {
        let model = DuplicatesModel()
        model.preview([group(size: 1_000, files: 2)])
        model.minimumSize = 10_000
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertEqual(model.totalWasted, 0)
        XCTAssertEqual(model.minimumSize, 10_000)
    }
}
