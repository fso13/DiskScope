import AppKit
import Foundation
import XCTest
@testable import DiskScopeKit

final class SimilarImageTests: XCTestCase {
    func testGreedyClustersNearVectors() {
        let features = [
            ImageFeature(index: 0, vector: [1, 0]),
            ImageFeature(index: 1, vector: [1.05, 0]),
            ImageFeature(index: 2, vector: [0, 1]),
            ImageFeature(index: 3, vector: [0.02, 1.02]),
            ImageFeature(index: 4, vector: [4, 4]),
        ]
        let groups = SimilarImageClusterer.cluster(features, threshold: 0.2)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.contains { Set($0) == Set<Int32>([0, 1]) })
        XCTAssertTrue(groups.contains { Set($0) == Set<Int32>([2, 3]) })
        XCTAssertFalse(groups.contains { $0.contains(4) })
    }

    func testThresholdAndGroupLimit() {
        let features = [
            ImageFeature(index: 0, vector: [1, 0]),
            ImageFeature(index: 1, vector: [1.05, 0]),
        ]
        XCTAssertTrue(SimilarImageClusterer.cluster(features, threshold: 0.01).isEmpty)
        XCTAssertEqual(SimilarImageClusterer.cluster(features, threshold: 0.2).count, 1)

        let many = [
            ImageFeature(index: 0, vector: [1, 0]),
            ImageFeature(index: 1, vector: [0, 1]),
            ImageFeature(index: 2, vector: [1, 0]),
            ImageFeature(index: 3, vector: [0, 1]),
        ]
        XCTAssertEqual(SimilarImageClusterer.cluster(many, threshold: 0.1, maxGroups: 1).count, 1)
    }

    func testCandidatesSkipPackagesTextAndHardLinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeSimilar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("App.app/Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        let image = root.appendingPathComponent("photo.png")
        try Data(repeating: 0x41, count: 1_000).write(to: image)
        try Data(repeating: 0x42, count: 1_000).write(to: root.appendingPathComponent("notes.txt"))
        try Data(repeating: 0x43, count: 1_000).write(to: root.appendingPathComponent("App.app/Contents/inner.png"))
        try FileManager.default.linkItem(at: image, to: root.appendingPathComponent("photo-link.png"))

        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        let candidates = SimilarImageFinder.candidateIndices(
            tree: tree,
            options: SimilarImageOptions(minimumSize: 0, maximumImages: 100)
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(tree.name(of: candidates[0]), "photo.png")
    }

    func testVisionFindsIdenticalScreenshots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeVision-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 32).fill()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 32, width: 64, height: 32).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

        try png.write(to: root.appendingPathComponent("shot.png"))
        try png.write(to: root.appendingPathComponent("shot-copy.png"))

        let tree = try DiskScanner(options: .detailed).scan(path: root.path)
        let result = SimilarImageFinder.find(
            tree: tree,
            options: SimilarImageOptions(minimumSize: 0, maximumImages: 10, threshold: 0.5)
        )
        XCTAssertTrue(result.groups.contains { group in
            let names = Set(group.images.map { ($0.path as NSString).lastPathComponent })
            return names == Set(["shot.png", "shot-copy.png"])
        })
    }
}
