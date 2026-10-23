import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class SimilarModelTests: XCTestCase {
    func testPreviewAndOptionsReset() {
        let images = [
            SimilarImage(index: 1, path: "/tmp/a", relativePath: "a", size: 10, modified: nil),
            SimilarImage(index: 2, path: "/tmp/b", relativePath: "b", size: 10, modified: nil),
        ]
        let group = SimilarImageGroup(id: "g", images: images)
        let model = SimilarModel()
        model.preview([group])
        XCTAssertEqual(model.state.groups.count, 1)
        XCTAssertEqual(model.state.candidateCount, 2)
        XCTAssertEqual(model.state.progress, 1)

        model.options.threshold = 0.9
        XCTAssertTrue(model.state.groups.isEmpty)
        XCTAssertEqual(model.options.threshold, 0.9)
    }
}
