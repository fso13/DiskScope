import Combine
import Foundation
import XCTest
@testable import DiskScopeKit

final class MediaSearchTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeMediaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        try write("Pictures/one.jpg", bytes: 100)
        try write("Pictures/nested/two.PNG", bytes: 200)
        try write("Music/song.mp3", bytes: 300)
        try write("Movies/clip.mov", bytes: 400)
        try write("Docs/report.pdf", bytes: 500)
        try write("Docs/letter.DOCX", bytes: 600)
        try write("Docs/sheet.xlsx", bytes: 700)
        try write("Docs/notes.md", bytes: 800)
        try write("Code/main.swift", bytes: 900)
        try write("Pictures/.hidden/secret.jpg", bytes: 1_000)
        try write("Pictures/Bundle.app/Contents/inside.jpg", bytes: 1_100)

        try FileManager.default.createSymbolicLink(
            at: scratch.appendingPathComponent("Pictures/link.jpg"),
            withDestinationURL: scratch.appendingPathComponent("Pictures/one.jpg")
        )
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        try super.tearDownWithError()
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int) throws -> URL {
        let url = scratch.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x42, count: bytes).write(to: url)
        return url
    }

    private func search(_ types: Set<MediaType>, folders: [URL]? = nil, maxResults: Int = 25_000) throws -> MediaSearchResult {
        let engine = MediaSearchEngine()
        return try engine.search(
            options: MediaSearchOptions(
                folders: folders ?? [scratch],
                types: types,
                maxResults: maxResults
            )
        )
    }

    func testImageSearchSkipsHiddenPackagesAndSymlinks() throws {
        let result = try search([.image])
        XCTAssertEqual(result.files.count, 2)
        XCTAssertEqual(Set(result.files.map(\.name)), ["one.jpg", "two.PNG"])
        XCTAssertTrue(result.files.allSatisfy { $0.kind == .image })
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.files.reduce(Int64(0)) { $0 + $1.size }, 300)
    }

    func testSpecificAndBroadTypes() throws {
        XCTAssertEqual(try search([.audio]).files.map(\.name), ["song.mp3"])
        XCTAssertEqual(try search([.video]).files.map(\.name), ["clip.mov"])
        XCTAssertEqual(try search([.pdf]).files.map(\.name), ["report.pdf"])
        XCTAssertEqual(try search([.doc]).files.map(\.name), ["letter.DOCX"])

        let documents = try search([.document])
        XCTAssertEqual(documents.files.count, 3)
        XCTAssertEqual(Set(documents.files.map(\.kind)), [.pdf, .doc, .document])
        XCTAssertFalse(documents.files.contains { $0.name == "notes.md" })
    }

    func testMediaKindMapping() {
        XCTAssertEqual(MediaKind.forExtension("JPG"), .image)
        XCTAssertEqual(MediaKind.forExtension("mp3"), .audio)
        XCTAssertEqual(MediaKind.forExtension("mov"), .video)
        XCTAssertEqual(MediaKind.forExtension("pdf"), .pdf)
        XCTAssertEqual(MediaKind.forExtension("docx"), .doc)
        XCTAssertEqual(MediaKind.forExtension("xlsx"), .document)
        XCTAssertNil(MediaKind.forExtension("swift"))
    }

    func testOverlappingFoldersDoNotDuplicateResults() throws {
        let pictures = scratch.appendingPathComponent("Pictures", isDirectory: true)
        let result = try search([.image], folders: [pictures, scratch])
        XCTAssertEqual(result.files.count, 2)
        XCTAssertEqual(Set(result.files.map(\.path)).count, 2)
    }

    func testRelativePathAndSourceRoot() throws {
        let result = try search([.image])
        let nested = try XCTUnwrap(result.files.first { $0.name == "two.PNG" })
        XCTAssertEqual(nested.relativePath, "Pictures/nested/two.PNG")
        XCTAssertEqual(nested.sourceRoot, scratch.standardizedFileURL.path)
    }

    func testMaxResultsTruncates() throws {
        let result = try search([.image], maxResults: 1)
        XCTAssertEqual(result.files.count, 1)
        XCTAssertTrue(result.truncated)
    }

    func testCancellation() throws {
        let token = ScanCancellation()
        token.cancel()
        let engine = MediaSearchEngine()
        XCTAssertThrowsError(
            try engine.search(
                options: MediaSearchOptions(folders: [scratch], types: [.image]),
                cancellation: token
            )
        ) { error in
            guard case MediaSearchError.cancelled = error else {
                return XCTFail("expected cancellation, got \(error)")
            }
        }
    }

    func testNoTypesAndNoFoldersThrow() {
        let engine = MediaSearchEngine()
        XCTAssertThrowsError(
            try engine.search(options: MediaSearchOptions(folders: [scratch], types: []))
        )
        XCTAssertThrowsError(
            try engine.search(options: MediaSearchOptions(folders: [], types: [.image]))
        )
    }
}

final class MediaMoverTests: XCTestCase {
    private var scratch: URL!
    private var source: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeMoveTests-\(UUID().uuidString)", isDirectory: true)
        source = scratch.appendingPathComponent("source", isDirectory: true)
        destination = scratch.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        try super.tearDownWithError()
    }

    @discardableResult
    private func makeFile(_ name: String, in directory: URL, bytes: Int = 10) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    private func mediaFile(_ url: URL) -> MediaFile {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return MediaFile(path: url.path, size: size, kind: .image)
    }

    func testMovesFilesAndRemovesSource() throws {
        let file = try makeFile("one.jpg", in: source, bytes: 12)
        let item = mediaFile(file)
        let result = MediaMover().move(files: [item], to: destination)

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.moved.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("one.jpg").path))
        XCTAssertEqual(result.movedBytes, 12)
    }

    func testCollisionGetsNumericSuffix() throws {
        let file = try makeFile("one.jpg", in: source, bytes: 12)
        try makeFile("one.jpg", in: destination, bytes: 5)

        let result = MediaMover().move(files: [mediaFile(file)], to: destination)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("one 2.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("one.jpg").path))
    }

    func testAlreadyInDestinationIsReported() throws {
        let file = try makeFile("one.jpg", in: destination, bytes: 12)
        let result = MediaMover().move(files: [mediaFile(file)], to: destination)

        XCTAssertTrue(result.moved.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].message.contains("уже находится"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testMissingFileIsReportedWithoutTouchingDestination() throws {
        let missing = MediaFile(path: source.appendingPathComponent("missing.jpg").path, size: 0, kind: .image)
        let result = MediaMover().move(files: [missing], to: destination)

        XCTAssertTrue(result.moved.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].message.contains("не найден"))
    }

    func testMovesMultipleAndKeepsNamesUnique() throws {
        let first = try makeFile("photo.png", in: source, bytes: 1)
        let second = try makeFile("photo.png", in: source.appendingPathComponent("sub", isDirectory: true), bytes: 2)
        let result = MediaMover().move(files: [mediaFile(first), mediaFile(second)], to: destination)

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.moved.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("photo.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("photo 2.png").path))
    }
}

final class PhotosImporterTests: XCTestCase {
    private func file(_ name: String) -> MediaFile {
        MediaFile(path: "/tmp/\(name)", size: 0, kind: .image)
    }

    func testSupportedImageExtensions() {
        XCTAssertTrue(PhotosImporter.supports(file("photo.JPG")))
        XCTAssertTrue(PhotosImporter.supports(file("photo.heic")))
        XCTAssertTrue(PhotosImporter.supports(file("photo.png")))
        XCTAssertFalse(PhotosImporter.supports(file("design.psd")))
        XCTAssertFalse(PhotosImporter.supports(file("design.svg")))
        XCTAssertFalse(PhotosImporter.supports(MediaFile(path: "/tmp/song.mp3", size: 0, kind: .audio)))
    }
}

@MainActor
final class MediaModelTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeMediaModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try write("source/photo.jpg", bytes: 120)
        try write("source/report.pdf", bytes: 240)
        try FileManager.default.createDirectory(
            at: scratch.appendingPathComponent("destination", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        try super.tearDownWithError()
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int) throws -> URL {
        let url = scratch.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    func testSearchSelectAndMoveFlow() async throws {
        let media = MediaModel()
        media.addSource(scratch.appendingPathComponent("source", isDirectory: true))
        media.setTypes([.image])

        let searched = expectation(description: "search finished")
        var bag = Set<AnyCancellable>()
        media.$isSearching
            .dropFirst()
            .sink { isSearching in
                if !isSearching { searched.fulfill() }
            }
            .store(in: &bag)

        media.search()
        await fulfillment(of: [searched], timeout: 10)
        XCTAssertEqual(media.results.count, 1)
        XCTAssertEqual(media.results.first?.name, "photo.jpg")

        media.selectedIDs = Set(media.results.map(\.id))
        media.destination = scratch.appendingPathComponent("destination", isDirectory: true)

        let moved = expectation(description: "move finished")
        media.$isMoving
            .dropFirst()
            .sink { isMoving in
                if !isMoving { moved.fulfill() }
            }
            .store(in: &bag)

        media.moveSelected()
        await fulfillment(of: [moved], timeout: 10)

        XCTAssertTrue(media.results.isEmpty)
        XCTAssertTrue(media.selectedIDs.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: scratch.appendingPathComponent("source/photo.jpg").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: scratch.appendingPathComponent("destination/photo.jpg").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: scratch.appendingPathComponent("source/report.pdf").path
            )
        )
    }

    func testSourceSelectionInvalidatesResults() async throws {
        let media = MediaModel()
        media.addSource(scratch.appendingPathComponent("source", isDirectory: true))
        media.setTypes([.image])

        let searched = expectation(description: "search finished")
        var bag = Set<AnyCancellable>()
        media.$isSearching.dropFirst().sink { if !$0 { searched.fulfill() } }.store(in: &bag)
        media.search()
        await fulfillment(of: [searched], timeout: 10)
        XCTAssertFalse(media.results.isEmpty)

        media.toggleType(.image)
        media.toggleType(.pdf)
        XCTAssertFalse(media.hasSearched)
        XCTAssertTrue(media.results.isEmpty)
    }
}
