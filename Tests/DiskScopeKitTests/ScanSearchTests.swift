import Foundation
import XCTest
@testable import DiskScopeKit

final class ScanSearchTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try write("Reports/Annual Report.PDF", bytes: 1_000_000)
        try write("Reports/notes.txt", bytes: 10_000)
        try write("Ёлка.txt", bytes: 1_000)
        try write("Sub/Foo.txt", bytes: 5_000)
        try write("Sub/bar.bin", bytes: 2_000_000)
        try write("Project/App.app/Contents/Info.plist", bytes: 2_000)
        try write("old.bin", bytes: 3_000_000, modified: Date(timeIntervalSince1970: 1_600_000_000))
        try write("recent.mov", bytes: 4_000_000, modified: now.addingTimeInterval(-5 * 86_400))
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    @discardableResult
    private func write(_ relativePath: String, bytes: Int, modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    private func index(minimumFileSize: Int64 = 0) throws -> ScanSearchIndex {
        let tree = try DiskScanner(options: ScanOptions(minimumFileSize: minimumFileSize)).scan(path: root.path)
        return ScanSearchIndex(tree: tree)
    }

    private func search(
        _ text: String,
        in index: ScanSearchIndex,
        minimumSize: Int64 = 0,
        category: FileCategory? = nil,
        kind: SearchKind = .any,
        dateRange: SearchDateRange = .any,
        sort: SearchSort = .size,
        limit: Int = 500
    ) -> SearchResults {
        index.search(SearchQuery(
            text: text,
            minimumSize: minimumSize,
            category: category,
            kind: kind,
            dateRange: dateRange,
            sort: sort,
            limit: limit,
            now: now
        ))
    }

    func testNameSearchIsCaseAndDiacriticInsensitive() throws {
        let index = try index()

        XCTAssertEqual(
            search("елка", in: index).hits.map(\.name),
            ["Ёлка.txt"]
        )
        XCTAssertEqual(
            search("ANNUAL REPORT", in: index).hits.map(\.name),
            ["Annual Report.PDF"]
        )
        let report = search("report", in: index).hits.first { $0.kind == .file }
        XCTAssertEqual(report?.relativePath, "Reports/Annual Report.PDF")
    }

    func testPathSearch() throws {
        let index = try index()
        let results = search("Reports/Annual", in: index)
        XCTAssertEqual(results.hits.count, 1)
        XCTAssertEqual(results.hits.first?.name, "Annual Report.PDF")

        let sub = search("sub/foo", in: index)
        XCTAssertEqual(sub.hits.map(\.name), ["Foo.txt"])
    }

    func testPackagesAreSingleItemsAndContentsAreHidden() throws {
        let index = try index()

        XCTAssertTrue(search("Info", in: index).hits.isEmpty)
        let packages = search("App.app", in: index)
        XCTAssertEqual(packages.hits.map(\.name), ["App.app"])
        XCTAssertEqual(packages.hits.first?.kind, .package)
    }

    func testKindAndCategoryFilters() throws {
        let index = try index()

        let files = search("txt", in: index, kind: .files)
        XCTAssertEqual(files.total, 3)
        XCTAssertTrue(files.hits.allSatisfy { $0.kind == .file })

        let folders = search("Sub", in: index, kind: .folders)
        XCTAssertEqual(folders.hits.map(\.name), ["Sub"])

        let videos = search("", in: index, category: .video)
        XCTAssertTrue(videos.hits.isEmpty, "Empty text must not search")

        let mov = search("recent", in: index, category: .video)
        XCTAssertEqual(mov.hits.map(\.name), ["recent.mov"])

        let pdf = search("report", in: index, category: .document, kind: .files)
        XCTAssertEqual(pdf.hits.map(\.name), ["Annual Report.PDF"])
    }

    func testSizeAndDateFilters() throws {
        let index = try index()

        let large = search("b", in: index, minimumSize: 2_500_000)
        XCTAssertEqual(large.hits.map(\.name), ["old.bin"])

        let month = search("bar", in: index, dateRange: .month)
        XCTAssertTrue(month.hits.isEmpty)

        let recent = search("recent", in: index, dateRange: .month)
        XCTAssertEqual(recent.hits.map(\.name), ["recent.mov"])

        let year = search("bar", in: index, dateRange: .year)
        XCTAssertEqual(year.hits.map(\.name), ["bar.bin"])
        XCTAssertTrue(search("old", in: index, dateRange: .year).hits.isEmpty)

        let older = search("old", in: index, dateRange: .older)
        XCTAssertEqual(older.hits.map(\.name), ["old.bin"])
    }

    func testSortingAndLimit() throws {
        let index = try index()

        let bySize = search("b", in: index)
        XCTAssertEqual(bySize.hits.first?.name, "old.bin")

        let limited = search("txt", in: index, limit: 2)
        XCTAssertEqual(limited.total, 3)
        XCTAssertEqual(limited.hits.count, 2)
        XCTAssertTrue(limited.truncated)

        let byName = search("txt", in: index, sort: .name)
        XCTAssertEqual(
            Set(byName.hits.map(\.name)),
            Set(["Foo.txt", "notes.txt", "Ёлка.txt"])
        )
    }

    func testAggregatesAreExcluded() throws {
        try write("tiny.dat", bytes: 10)
        let index = try index(minimumFileSize: 64 * 1024)
        XCTAssertTrue(search("tiny", in: index).hits.isEmpty)
        XCTAssertEqual(search("Sub", in: index, kind: .folders).hits.map(\.name), ["Sub"])
    }

    func testEmptyQueryReturnsNothing() throws {
        let index = try index()
        XCTAssertTrue(search("   ", in: index).hits.isEmpty)
        XCTAssertEqual(search("   ", in: index).total, 0)
    }
}
