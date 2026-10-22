import Foundation
import XCTest
@testable import DiskScopeKit

final class ReportExporterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeReport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try write("video.mov", bytes: 2_000_000)
        try write("notes.txt", bytes: 1_000)
        try write("Sub/cache.bin", bytes: 3_000)
        try write("Документы/план;2026.txt", bytes: 2_000)
        try write("Документы/<script>.txt", bytes: 1_000)
        try write("Документы/quote\".txt", bytes: 1_000)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    @discardableResult
    private func write(_ relativePath: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    private func scan() throws -> ScanTree {
        try DiskScanner(options: ScanOptions(minimumFileSize: 0)).scan(path: root.path)
    }

    private func options(
        scope: ReportScope,
        search: String = "",
        category: FileCategory? = nil,
        limit: Int = 10_000
    ) -> ReportOptions {
        ReportOptions(
            scope: scope,
            search: search,
            category: category,
            limit: limit,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appVersion: "9.9.9"
        )
    }

    private func documentsIndex(in tree: ScanTree) throws -> Int32 {
        try XCTUnwrap(tree.children(of: 0).first { tree.name(of: $0) == "Документы" })
    }

    private func csvRows(_ csv: String) -> [String] {
        csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.dropFirst().map { $0 }
    }

    // MARK: - CSV

    func testCSVHeaderAndEscaping() throws {
        try write("Документы/=SUM(1).txt", bytes: 10)
        let tree = try scan()
        let documents = try documentsIndex(in: tree)
        let csv = ReportExporter.makeCSV(
            tree: tree,
            rootIndex: documents,
            options: options(scope: .currentFolder)
        )

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Путь;Имя;Размер (байт);Доля (%);Категория;Тип;Изменён;Элементов"))
        XCTAssertTrue(csv.contains("\"план;2026.txt\""))
        XCTAssertTrue(csv.contains("\"quote\"\".txt\""))
        XCTAssertTrue(csv.contains("<script>.txt"))
        XCTAssertTrue(csv.contains("'=SUM(1).txt"))
        XCTAssertEqual(csvRows(csv).count, 4)
    }

    func testCSVScopeSearchCategoryAndLimit() throws {
        let tree = try scan()
        let documents = try documentsIndex(in: tree)

        let current = ReportExporter.makeCSV(
            tree: tree,
            rootIndex: documents,
            options: options(scope: .currentFolder)
        )
        XCTAssertTrue(current.contains("план;2026.txt"))
        XCTAssertFalse(current.contains("video.mov"))

        let whole = ReportExporter.makeCSV(
            tree: tree,
            rootIndex: 0,
            options: options(scope: .wholeScan)
        )
        XCTAssertTrue(whole.contains("план;2026.txt"))
        XCTAssertTrue(whole.contains("video.mov"))

        let search = ReportExporter.makeCSV(
            tree: tree,
            rootIndex: 0,
            options: options(scope: .wholeScan, search: "план")
        )
        XCTAssertTrue(search.contains("план;2026.txt"))
        XCTAssertFalse(search.contains("video.mov"))

        let video = ReportExporter.makeCSV(
            tree: tree,
            rootIndex: 0,
            options: options(scope: .wholeScan, category: .video)
        )
        XCTAssertTrue(video.contains("video.mov"))
        XCTAssertFalse(video.contains("notes.txt"))

        let one = ReportExporter.makeCSV(
            tree: tree,
            rootIndex: 0,
            options: options(scope: .wholeScan, limit: 1)
        )
        XCTAssertEqual(csvRows(one).count, 1)
    }

    func testWriteProducesUTF8BOM() throws {
        let tree = try scan()
        let csv = ReportExporter.makeCSV(
            tree: tree,
            rootIndex: 0,
            options: options(scope: .currentFolder)
        )
        let url = root.appendingPathComponent("report.csv")
        try ReportExporter.write(csv, to: url)

        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(data, Data(csv.utf8))
    }

    // MARK: - HTML

    func testHTMLIsSelfContainedAndEscaped() throws {
        let tree = try scan()
        let html = ReportExporter.makeHTML(
            tree: tree,
            rootIndex: 0,
            options: options(scope: .wholeScan)
        )

        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("prefers-color-scheme"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("http://"))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertTrue(html.contains("DiskScope 9.9.9"))
        XCTAssertTrue(html.contains("Видео"))
        XCTAssertTrue(html.contains("Занято"))
    }

    func testHTMLEmptyState() throws {
        let tree = try scan()
        let documents = try documentsIndex(in: tree)
        let html = ReportExporter.makeHTML(
            tree: tree,
            rootIndex: documents,
            options: options(scope: .currentFolder, search: "no-such-file")
        )
        XCTAssertTrue(html.contains("Нет объектов"))
    }

    func testFormatAndScopeTitles() {
        XCTAssertEqual(ReportFormat.csv.fileExtension, "csv")
        XCTAssertEqual(ReportFormat.html.fileExtension, "html")
        XCTAssertEqual(ReportScope.currentFolder.title, "Текущая папка")
        XCTAssertEqual(ReportScope.wholeScan.title, "Весь скан")
    }
}
