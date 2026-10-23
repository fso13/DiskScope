import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class ScanControllerTests: XCTestCase {
    func testPreviewAndCancelWithoutTree() {
        let model = ScanController()
        model.previewScanning(
            path: "/tmp/scan",
            progress: ScanProgress(entries: 3, currentPath: "/tmp/scan")
        )
        XCTAssertEqual(model.phase, .scanning)
        XCTAssertEqual(model.progress?.entries, 3)
        XCTAssertEqual(model.lastScanPath, "/tmp/scan")

        model.cancel()
        XCTAssertEqual(model.phase, .welcome)
        XCTAssertNil(model.progress)
    }
}
