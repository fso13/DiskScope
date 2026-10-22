import CoreGraphics
import XCTest
@testable import DiskScopeKit

final class TreemapNavigationTests: XCTestCase {
    private func cell(_ id: Int, node: Int32, rect: CGRect, depth: Int = 1) -> TreemapCell {
        TreemapCell(
            id: id,
            node: node,
            parentID: nil,
            depth: depth,
            rect: rect,
            size: 100,
            fraction: 0.1,
            name: "Cell \(id)",
            category: .other,
            isContainer: false,
            restCount: 0
        )
    }

    func testMovesSpatially() {
        let cells = [
            cell(1, node: 1, rect: CGRect(x: 0, y: 0, width: 100, height: 100)),
            cell(2, node: 2, rect: CGRect(x: 120, y: 0, width: 100, height: 100)),
            cell(3, node: 3, rect: CGRect(x: 0, y: 120, width: 100, height: 100)),
        ]

        XCTAssertEqual(TreemapNavigation.nextNode(from: 1, cells: cells, direction: .right), 2)
        XCTAssertEqual(TreemapNavigation.nextNode(from: 1, cells: cells, direction: .down), 3)
        XCTAssertEqual(TreemapNavigation.nextNode(from: 2, cells: cells, direction: .left), 1)
        XCTAssertEqual(TreemapNavigation.nextNode(from: 3, cells: cells, direction: .up), 1)
        XCTAssertNil(TreemapNavigation.nextNode(from: 1, cells: cells, direction: .left))
        XCTAssertNil(TreemapNavigation.nextNode(from: 1, cells: cells, direction: .up))
    }

    func testIgnoresDeepAndUnclickableCells() {
        let cells = [
            cell(1, node: 1, rect: CGRect(x: 0, y: 0, width: 100, height: 100)),
            cell(2, node: 2, rect: CGRect(x: 120, y: 0, width: 100, height: 100), depth: 3),
            TreemapCell(
                id: 3,
                node: nil,
                parentID: nil,
                depth: 1,
                rect: CGRect(x: 120, y: 0, width: 100, height: 100),
                size: 100,
                fraction: 0.1,
                name: "Rest",
                category: .other,
                isContainer: false,
                restCount: 5
            ),
        ]
        XCTAssertNil(TreemapNavigation.nextNode(from: 1, cells: cells, direction: .right))
    }
}
