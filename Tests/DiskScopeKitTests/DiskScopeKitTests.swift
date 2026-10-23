import Darwin
import Foundation
import XCTest
@testable import DiskScopeKit

final class ScannerTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scratch.path)
            try? FileManager.default.removeItem(at: scratch)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    @discardableResult
    private func writeFile(_ relativePath: String, bytes: Int, fill: UInt8 = 0x41) throws -> URL {
        let url = scratch.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: fill, count: bytes).write(to: url)
        return url
    }

    private func makeFixture() throws -> URL {
        try writeFile("big.bin", bytes: 2 * 1024 * 1024)
        try writeFile("Sub/inner.bin", bytes: 1_500_000)
        try writeFile("Sub/deep/tiny.dat", bytes: 10)
        for index in 0..<5 {
            try writeFile("small-\(index).txt", bytes: 1024 + index)
        }
        try writeFile("Package.app/Contents/Info.plist", bytes: 800)
        try writeFile("Package.app/Contents/MacOS/binary", bytes: 300_000)
        try writeFile("Документы/заметка.txt", bytes: 4096)
        try FileManager.default.createDirectory(
            at: scratch.appendingPathComponent("EmptyDir"),
            withIntermediateDirectories: true
        )
        let link = scratch.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: scratch.appendingPathComponent("Sub"))
        let fileLink = scratch.appendingPathComponent("big-link.bin")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: scratch.appendingPathComponent("big.bin"))
        return scratch
    }

    private func scan(_ url: URL, threshold: Int64 = 64 * 1024) throws -> ScanTree {
        try DiskScanner(options: ScanOptions(minimumFileSize: threshold)).scan(path: url.path)
    }

    private func child(named name: String, in tree: ScanTree, parent: Int32 = 0) -> Int32? {
        tree.children(of: parent).first { tree.name(of: $0) == name }
    }

    private struct FileTimes {
        var created: timespec
        var modified: timespec
    }

    /// Sets creation and modification dates in one `setattrlist` call.
    private func setTimes(created: Date, modified: Date, at url: URL) throws {
        var list = attrlist()
        list.bitmapcount = 5
        list.commonattr = 0x0000_0200 | 0x0000_0400
        var times = FileTimes(
            created: timespec(tv_sec: Int(created.timeIntervalSince1970), tv_nsec: 0),
            modified: timespec(tv_sec: Int(modified.timeIntervalSince1970), tv_nsec: 0)
        )
        let result = withUnsafeMutablePointer(to: &times) { pointer in
            setattrlist(
                url.path,
                &list,
                UnsafeMutableRawPointer(pointer),
                MemoryLayout<FileTimes>.size,
                0
            )
        }
        XCTAssertEqual(result, 0, "setattrlist failed for \(url.path): \(errno)")
    }

    // MARK: - Tests

    func testScanTotalsMatchDU() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        XCTAssertGreaterThan(tree.totalSize, 0)
        XCTAssertGreaterThan(tree.totalFiles, 0)
        XCTAssertGreaterThan(tree.report.entriesRead, 0)
        XCTAssertGreaterThan(tree.report.duration, 0)

        let duBytes = try duSize(root)
        let delta = abs(tree.totalSize - duBytes)
        XCTAssertLessThanOrEqual(
            Double(delta) / Double(max(duBytes, 1)), 0.06,
            "Scanner total \(tree.totalSize) vs du \(duBytes)"
        )
    }

    func testTreeShapeAndAggregates() throws {
        let root = try makeFixture()
        let tree = try scan(root)

        XCTAssertNotNil(child(named: "big.bin", in: tree))
        XCTAssertNotNil(child(named: "Sub", in: tree))
        XCTAssertNotNil(child(named: "EmptyDir", in: tree))
        XCTAssertNotNil(child(named: "Документы", in: tree))

        let rootChildren = tree.children(of: 0)
        let aggregates = rootChildren.filter { tree.node($0).nodeKind == .aggregate }
        XCTAssertEqual(aggregates.count, 1)
        let aggregate = try XCTUnwrap(aggregates.first)
        XCTAssertGreaterThanOrEqual(Int(tree.node(aggregate).itemCount), 5)

        let details = try scan(root, threshold: 0)
        let detailAggregates = details.children(of: 0).filter { details.node($0).nodeKind == .aggregate }
        XCTAssertTrue(detailAggregates.isEmpty)
        XCTAssertGreaterThan(details.count, tree.count)
    }

    func testPackageIsOneItem() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        let package = try XCTUnwrap(child(named: "Package.app", in: tree))
        XCTAssertEqual(tree.node(package).nodeKind, .package)
        XCTAssertEqual(tree.category(of: package), .app)
        XCTAssertGreaterThan(tree.node(package).size, 0)
        XCTAssertFalse(tree.children(of: package).isEmpty)

        let items = tree.largestItems(limit: 100)
        XCTAssertTrue(items.contains(package))
        let paths = items.map { tree.path(of: $0) }
        XCTAssertFalse(paths.contains { $0.contains("Package.app/") })

        let appStat = tree.categoryStats().first { $0.category == .app }
        XCTAssertNotNil(appStat)
        XCTAssertGreaterThan(appStat?.size ?? 0, 0)
    }

    func testSymlinksAreNotFollowed() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        let big = try XCTUnwrap(child(named: "big.bin", in: tree))
        let bigSize = tree.node(big).size
        XCTAssertGreaterThan(bigSize, 0)
        XCTAssertLessThan(tree.totalSize, bigSize * 3)

        let link = try XCTUnwrap(child(named: "link", in: tree))
        XCTAssertEqual(tree.node(link).nodeKind, .symlink)
        XCTAssertEqual(tree.node(link).size, 0)
    }

    func testScannerReadsCreationAndModificationDates() throws {
        let root = try makeFixture()
        let folder = root.appendingPathComponent("Dated", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("note.txt")
        try Data(repeating: 0x41, count: 4096).write(to: file)
        try setTimes(
            created: Date(timeIntervalSince1970: 1_500_000_000),
            modified: Date(timeIntervalSince1970: 1_650_000_000),
            at: file
        )

        let tree = try scan(root, threshold: 0)
        let dated = try XCTUnwrap(child(named: "Dated", in: tree))
        let note = try XCTUnwrap(child(named: "note.txt", in: tree, parent: dated))

        XCTAssertEqual(tree.createdDay(of: note), ScanNode.dayNumber(seconds: 1_500_000_000))
        XCTAssertEqual(tree.modifiedDay(of: note), ScanNode.dayNumber(seconds: 1_650_000_000))
        XCTAssertEqual(
            tree.created(of: note),
            ScanNode.date(day: ScanNode.dayNumber(seconds: 1_500_000_000))
        )
        XCTAssertEqual(
            tree.modified(of: note),
            ScanNode.date(day: ScanNode.dayNumber(seconds: 1_650_000_000))
        )
        XCTAssertNotNil(tree.created(of: 0))
        XCTAssertNotNil(tree.modified(of: 0))
    }

    func testAggregateUsesOldestCreationAndLatestModification() throws {
        let root = scratch.appendingPathComponent("Aggregates", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldFile = root.appendingPathComponent("old.txt")
        let newFile = root.appendingPathComponent("new.txt")
        try Data(repeating: 1, count: 1024).write(to: oldFile)
        try Data(repeating: 2, count: 1024).write(to: newFile)
        try setTimes(
            created: Date(timeIntervalSince1970: 1_400_000_000),
            modified: Date(timeIntervalSince1970: 1_450_000_000),
            at: oldFile
        )
        try setTimes(
            created: Date(timeIntervalSince1970: 1_600_000_000),
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            at: newFile
        )

        let tree = try scan(root)
        let aggregate = try XCTUnwrap(
            tree.children(of: 0).first { tree.node($0).nodeKind == .aggregate }
        )
        XCTAssertEqual(tree.createdDay(of: aggregate), ScanNode.dayNumber(seconds: 1_400_000_000))
        XCTAssertEqual(tree.modifiedDay(of: aggregate), ScanNode.dayNumber(seconds: 1_700_000_000))
    }

    func testDayNumberConversion() {
        XCTAssertEqual(ScanNode.dayNumber(seconds: 978_307_200), 0)
        XCTAssertEqual(ScanNode.dayNumber(seconds: 978_307_199), -1)
        XCTAssertEqual(ScanNode.dayNumber(seconds: 978_307_200 + 86_399), 0)
        XCTAssertEqual(ScanNode.dayNumber(seconds: 978_307_200 + 86_400), 1)
        XCTAssertNil(ScanNode.date(day: ScanNode.unknownDay))
        XCTAssertEqual(ScanNode.creationDay(seconds: 0), ScanNode.unknownDay)
        XCTAssertEqual(ScanNode.creationDay(seconds: 1_500_000_000), ScanNode.dayNumber(seconds: 1_500_000_000))
        XCTAssertEqual(
            ScanNode.date(day: 0)?.timeIntervalSince1970 ?? 0,
            978_307_200 + 43_200,
            accuracy: 0.5
        )
    }

    func testUnicodePathsAndNames() throws {
        let root = try makeFixture()
        let tree = try scan(root, threshold: 0)
        let documents = try XCTUnwrap(child(named: "Документы", in: tree))
        XCTAssertEqual(tree.path(of: documents), root.path + "/Документы")
        let note = try XCTUnwrap(child(named: "заметка.txt", in: tree, parent: documents))
        XCTAssertEqual(tree.path(of: note), root.path + "/Документы/заметка.txt")
        XCTAssertEqual(tree.category(of: note), .document)
    }

    func testPermissionDeniedIsReportedNotFatal() throws {
        let secret = scratch.appendingPathComponent("Secret", isDirectory: true)
        try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100_000).write(to: secret.appendingPathComponent("hidden.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secret.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: secret.path)
        }

        let tree = try scan(scratch)
        XCTAssertGreaterThanOrEqual(tree.report.skippedItems, 1)
        XCTAssertFalse(tree.report.sampleSkippedPaths.isEmpty)
    }

    func testScanCancellation() throws {
        let root = try makeFixture()
        let token = ScanCancellation()
        token.cancel()
        XCTAssertThrowsError(try DiskScanner().scan(path: root.path, cancellation: token)) { error in
            guard case ScanError.cancelled = error else {
                return XCTFail("Expected cancellation, got \(error)")
            }
        }
    }

    func testScanningAFileFails() throws {
        let file = try writeFile("single.txt", bytes: 10)
        XCTAssertThrowsError(try DiskScanner().scan(path: file.path)) { error in
            guard case ScanError.notDirectory = error else {
                return XCTFail("Expected notDirectory, got \(error)")
            }
        }
    }

    func testPruningCreatesNewTreeAndUpdatesAncestors() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        let sub = try XCTUnwrap(child(named: "Sub", in: tree))
        let subSize = tree.node(sub).size
        let oldTotal = tree.totalSize
        let oldFiles = tree.totalFiles

        let result = tree.removingSubtrees(at: [sub])
        XCTAssertEqual(result.bytes, subSize)
        XCTAssertEqual(result.tree.totalSize, oldTotal - subSize)
        XCTAssertEqual(result.tree.totalFiles, oldFiles - result.files)
        XCTAssertFalse(result.tree.children(of: 0).contains(sub))
        XCTAssertTrue(tree.children(of: 0).contains(sub), "Original tree must stay untouched")
        XCTAssertEqual(tree.totalSize, oldTotal)
    }

    func testRestoringRemovalBringsBackSizesAndFiles() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        let sub = try XCTUnwrap(child(named: "Sub", in: tree))
        let inner = try XCTUnwrap(child(named: "inner.bin", in: tree, parent: sub))
        let oldTotal = tree.totalSize
        let oldFiles = tree.totalFiles
        let subSize = tree.node(sub).size

        let removal = tree.removingSubtrees(at: [sub])
        XCTAssertEqual(removal.groups.count, 1)
        let group = try XCTUnwrap(removal.groups.first)
        XCTAssertEqual(group.root, sub)
        XCTAssertTrue(group.marked.contains(sub))
        XCTAssertTrue(group.marked.contains(inner))
        XCTAssertEqual(group.bytes, subSize)

        let restored = removal.tree.restoringSubtrees(groups: removal.groups)
        XCTAssertFalse(restored.isDeleted(sub))
        XCTAssertFalse(restored.isDeleted(inner))
        XCTAssertEqual(restored.totalSize, oldTotal)
        XCTAssertEqual(restored.totalFiles, oldFiles)
        XCTAssertEqual(restored.node(sub).size, subSize)
    }

    func testUndoNestedRemovalKeepsEarlierDeletion() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        let sub = try XCTUnwrap(child(named: "Sub", in: tree))
        let inner = try XCTUnwrap(child(named: "inner.bin", in: tree, parent: sub))
        let oldTotal = tree.totalSize
        let oldFiles = tree.totalFiles

        let first = tree.removingSubtrees(at: [inner])
        let second = first.tree.removingSubtrees(at: [sub])

        let afterSecondUndo = second.tree.restoringSubtrees(groups: second.groups)
        XCTAssertFalse(afterSecondUndo.isDeleted(sub))
        XCTAssertTrue(afterSecondUndo.isDeleted(inner), "Earlier deletion must stay pending")
        XCTAssertEqual(afterSecondUndo.totalSize, first.tree.totalSize)
        XCTAssertEqual(afterSecondUndo.totalFiles, first.tree.totalFiles)

        let fullyRestored = afterSecondUndo.restoringSubtrees(groups: first.groups)
        XCTAssertFalse(fullyRestored.isDeleted(inner))
        XCTAssertEqual(fullyRestored.totalSize, oldTotal)
        XCTAssertEqual(fullyRestored.totalFiles, oldFiles)
    }

    func testRestoringRemovalIsIdempotent() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        let sub = try XCTUnwrap(child(named: "Sub", in: tree))
        let removal = tree.removingSubtrees(at: [sub])
        let restored = removal.tree.restoringSubtrees(groups: removal.groups)
        let restoredAgain = restored.restoringSubtrees(groups: removal.groups)

        XCTAssertEqual(restoredAgain.totalSize, restored.totalSize)
        XCTAssertEqual(restoredAgain.totalFiles, restored.totalFiles)
    }

    func testMultipleRemovalGroupsRestoreTogether() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        let sub = try XCTUnwrap(child(named: "Sub", in: tree))
        let big = try XCTUnwrap(child(named: "big.bin", in: tree))
        let oldTotal = tree.totalSize
        let oldFiles = tree.totalFiles

        let removal = tree.removingSubtrees(at: [sub, big])
        XCTAssertEqual(removal.groups.count, 2)

        let restored = removal.tree.restoringSubtrees(groups: removal.groups)
        XCTAssertEqual(restored.totalSize, oldTotal)
        XCTAssertEqual(restored.totalFiles, oldFiles)
        XCTAssertFalse(restored.isDeleted(sub))
        XCTAssertFalse(restored.isDeleted(big))
    }

    func testChildrenSumToParentSize() throws {
        let root = try makeFixture()
        let tree = try scan(root)
        for index in tree.children(of: 0) {
            guard tree.node(index).nodeKind.isContainer else { continue }
            let children = tree.children(of: index)
            let sum = children.reduce(Int64(0)) { $0 + tree.node($1).size }
            XCTAssertEqual(sum, tree.node(index).size, "Sizes must add up for \(tree.name(of: index))")
        }
    }

    private func duSize(_ url: URL) throws -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        guard let kibibytes = Int64(output.split(separator: "\t").first ?? "") else {
            XCTFail("Unexpected du output: \(output)")
            return 0
        }
        return kibibytes * 1024
    }
}

final class TreemapTests: XCTestCase {
    func testLayoutTilesTheRect() {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 500)
        let values: [Double] = [10, 6, 4, 3, 2, 1, 0.4, 0.2]
        let cells = TreemapLayout.layout(values: values, in: rect)
        XCTAssertEqual(cells.count, values.count)

        let totalArea = cells.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        XCTAssertEqual(totalArea, rect.width * rect.height, accuracy: 1)

        for (index, cell) in cells.enumerated() where values[index] > 0 {
            XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(cell), "Cell outside bounds")
            XCTAssertGreaterThan(cell.width, 0)
            XCTAssertGreaterThan(cell.height, 0)
        }

        let positive = values.enumerated().filter { $0.element > 0 }
        let firstRatio = cells[positive[0].offset].width * cells[positive[0].offset].height / CGFloat(positive[0].element)
        for (index, value) in positive {
            let ratio = cells[index].width * cells[index].height / CGFloat(value)
            XCTAssertEqual(ratio, firstRatio, accuracy: firstRatio * 0.01, "Area not proportional")
        }

        for i in cells.indices {
            for j in cells.indices where j > i {
                let overlap = cells[i].intersection(cells[j])
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height <= 1)
            }
        }
    }

    func testSingleValueFillsRect() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let cells = TreemapLayout.layout(values: [42], in: rect)
        XCTAssertEqual(cells[0].width, 300, accuracy: 0.01)
        XCTAssertEqual(cells[0].height, 200, accuracy: 0.01)
    }

    func testEmptyInput() {
        XCTAssertTrue(TreemapLayout.layout(values: [], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        let zero = TreemapLayout.layout(values: [0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(zero.count, 2)
    }

    func testBuilderCreatesNestedCells() throws {
        let tree = try SampleTree.make()
        let cells = TreemapBuilder.build(
            tree: tree,
            root: 0,
            size: CGSize(width: 1000, height: 650)
        )
        XCTAssertFalse(cells.isEmpty)
        let outer = cells.filter { $0.depth == 1 }
        let inner = cells.filter { $0.depth == 2 }
        XCTAssertFalse(outer.isEmpty)
        for cell in outer {
            XCTAssertTrue(cell.node != nil)
            XCTAssertLessThanOrEqual(cell.fraction, 1.0001)
        }
        for cell in inner {
            let parentID = try XCTUnwrap(cell.parentID)
            let parent = try XCTUnwrap(outer.first { $0.id == parentID })
            XCTAssertTrue(parent.rect.contains(cell.rect.insetBy(dx: 0.5, dy: 0.5)))
            XCTAssertTrue(cell.fraction > 0 && cell.fraction <= 1.0001)
        }
        XCTAssertTrue(cells.contains { $0.restCount > 0 } || outer.count < 5)
    }
}

final class ModelHelperTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("ru", forKey: "app.settings.language")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "app.settings.language")
        super.tearDown()
    }

    func testByteFormatting() {
        XCTAssertEqual(ByteFormat.string(0), "0 Б")
        XCTAssertTrue(ByteFormat.string(1_500).contains("КБ"))
        XCTAssertTrue(ByteFormat.string(5_300_000_000).contains("ГБ"))
        XCTAssertEqual(ByteFormat.percent(0, of: 100), "0%")
        XCTAssertEqual(ByteFormat.percent(100, of: 100), "100%")
    }

    func testRussianPlurals() {
        XCTAssertTrue(Plural.files(1).contains("файл"))
        XCTAssertTrue(Plural.files(3).contains("файла"))
        XCTAssertTrue(Plural.files(11).contains("файлов"))
        XCTAssertTrue(Plural.apps(2).contains("приложения"))
    }

    func testVolumeList() {
        let volumes = VolumeInfo.loadAll()
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertTrue(volumes.contains { $0.path == "/" })
        XCTAssertGreaterThan(volumes[0].totalBytes, 0)
    }

    func testCategoryMapping() {
        XCTAssertEqual(FileCategory.forExtension("MOV"), .video)
        XCTAssertEqual(FileCategory.forExtension("heic"), .image)
        XCTAssertEqual(FileCategory.forExtension("mp3"), .audio)
        XCTAssertEqual(FileCategory.forExtension("zip"), .archive)
        XCTAssertEqual(FileCategory.forExtension("pdf"), .document)
        XCTAssertEqual(FileCategory.forExtension("swift"), .code)
        XCTAssertEqual(FileCategory.forExtension("xyz"), .other)
    }
}

/// Builds a small on-disk sample and scans it, used by the treemap tests.
enum SampleTree {
    static func make() throws -> ScanTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeTree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let folders = ["Projects", "Media", "Backups"]
        for folder in folders {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(folder),
                withIntermediateDirectories: true
            )
            for index in 0..<4 {
                let data = Data(repeating: UInt8(index + 1), count: (index + 1) * 120_000)
                try data.write(to: root.appendingPathComponent("\(folder)/file-\(index).bin"))
            }
        }
        return try DiskScanner(options: ScanOptions(minimumFileSize: 64 * 1024)).scan(path: root.path)
    }
}
