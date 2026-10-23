import XCTest
@testable import DiskScopeKit

final class MenuBarStatusTests: XCTestCase {
    func testFreeAndPercentTitles() {
        let volume = VolumeInfo(
            id: "/",
            name: "Test",
            path: "/",
            totalBytes: 4_000,
            freeBytes: 1_000,
            importantFreeBytes: 1_500,
            isInternal: true,
            isRemovable: false
        )
        let status = MenuBarStatus(volume: volume)
        XCTAssertEqual(status.usedBytes, 3_000)
        XCTAssertEqual(status.usedFraction, 0.75, accuracy: 0.001)
        XCTAssertTrue(status.title(.free).contains("1"))
        XCTAssertEqual(status.title(.percent), "25%")
        XCTAssertTrue(status.accessibilityLabel(.free).contains("free"))
    }

    func testZeroVolumeIsSafe() {
        let status = MenuBarStatus(freeBytes: 0, totalBytes: 0, purgeableBytes: 0)
        XCTAssertEqual(status.usedBytes, 0)
        XCTAssertEqual(status.usedFraction, 0)
        XCTAssertEqual(status.title(.percent), "0%")
    }
}
