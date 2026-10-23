import Foundation
import XCTest
@testable import DiskScopeKit

@MainActor
final class ReportModelTests: XCTestCase {
    private func makeTree() throws -> ScanTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeReportModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 5_000).write(to: root.appendingPathComponent("video.mov"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try DiskScanner(options: .detailed).scan(path: root.path)
    }

    private func makeModel(
        tree: ScanTree?,
        currentIndex: Int32 = 0,
        search: String = "",
        category: FileCategory? = nil,
        currentName: String = "",
        rootName: String = "DiskScope",
        version: String = "dev"
    ) -> ReportModel {
        let model = ReportModel(versionProvider: { version })
        model.attach(
            treeProvider: { tree },
            currentIndexProvider: { currentIndex },
            searchProvider: { search },
            categoryProvider: { category },
            currentNameProvider: { currentName },
            rootDisplayNameProvider: { rootName },
            toast: { _, _ in },
            error: { _ in }
        )
        return model
    }

    func testCanExportReportFollowsTree() throws {
        let tree = try makeTree()
        XCTAssertTrue(makeModel(tree: tree).canExportReport)
        XCTAssertFalse(makeModel(tree: nil).canExportReport)
    }

    func testDefaultReportFilenameSanitizesAndFallsBack() {
        let model = makeModel(tree: nil, currentName: "Folder: A/B", rootName: "Root")
        XCTAssertEqual(
            model.defaultReportFilename(format: .csv, scope: .currentFolder),
            "DiskScope-Folder- A-B.csv"
        )
        XCTAssertEqual(
            model.defaultReportFilename(format: .html, scope: .wholeScan),
            "DiskScope-Root.html"
        )

        let fallback = makeModel(tree: nil, currentName: "   ", rootName: "")
        XCTAssertEqual(
            fallback.defaultReportFilename(format: .csv, scope: .currentFolder),
            "DiskScope-DiskScope.csv"
        )
        XCTAssertEqual(
            fallback.defaultReportFilename(format: .csv, scope: .wholeScan),
            "DiskScope-DiskScope.csv"
        )
    }

    func testOptionsCaptureFiltersScopeAndVersion() {
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let model = makeModel(
            tree: nil,
            search: "video",
            category: .video,
            version: "9.9.9"
        )
        let options = model.options(format: .html, scope: .wholeScan, generatedAt: generatedAt)

        XCTAssertEqual(options.format, .html)
        XCTAssertEqual(options.scope, .wholeScan)
        XCTAssertEqual(options.search, "video")
        XCTAssertEqual(options.category, .video)
        XCTAssertEqual(options.generatedAt, generatedAt)
        XCTAssertEqual(options.appVersion, "9.9.9")
        XCTAssertEqual(model.appVersion, "9.9.9")
    }
}
