import Foundation
import XCTest
@testable import DiskScopeKit

final class CleanupRulesTests: XCTestCase {
    private var home: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskScopeCleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home {
            try? FileManager.default.removeItem(at: home)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    @discardableResult
    private func makeDirectory(_ relativePath: String) throws -> URL {
        let url = home.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeFile(
        _ relativePath: String,
        bytes: Int = 1024,
        modified: Date? = nil
    ) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
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

    private func setModified(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    private func makeHomeFixture() throws {
        try writeFile(".Trash/old.bin", bytes: 4096)

        try writeFile("Library/Developer/Xcode/DerivedData/App/Build/app", bytes: 8192)

        try makeDirectory("Library/Developer/Xcode/Archives/2025-01-01/App.xcarchive")
        try writeFile("Library/Developer/Xcode/Archives/2025-01-01/App.xcarchive/Info.plist")
        try setModified(daysAgo(200), at: home.appendingPathComponent("Library/Developer/Xcode/Archives/2025-01-01"))

        try writeFile("Library/Developer/Xcode/iOS DeviceSupport/18.0/Symbols/UIKit", bytes: 4096)

        // 51 MB child cache: above the 50 MB threshold.
        try writeFile("Library/Caches/com.example.app/cache.bin", bytes: 51 * 1024 * 1024)
        try writeFile("Library/Caches/Homebrew/bottle.tar.gz")

        try writeFile("Downloads/old.dmg", modified: daysAgo(40))
        try writeFile("Downloads/new.dmg", modified: daysAgo(1))
        try writeFile("Downloads/notes.txt", modified: daysAgo(40))

        try makeDirectory("Library/Application Support/MobileSync/Backup/DEVICE")
        try writeFile("Library/Application Support/MobileSync/Backup/DEVICE/Manifest.db")
        try setModified(
            daysAgo(200),
            at: home.appendingPathComponent("Library/Application Support/MobileSync/Backup/DEVICE")
        )

        try writeFile("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", bytes: 4096)
        try writeFile(".gradle/caches/modules.bin")
        try writeFile(".m2/repository/org/example/lib.jar")
        try writeFile(".npm/_cacache/content.bin")
        try writeFile("Library/Developer/CoreSimulator/Caches/cache.bin")
        try writeFile("Library/Developer/Xcode/UserData/IDETemplateMacros.plist")
        try writeFile("Projects/app/node_modules/pkg/index.js")
        try writeFile("Projects/App.app/Contents/Resources/node_modules/ignored.js")
    }

    private func scan(_ url: URL? = nil) throws -> ScanTree {
        try DiskScanner(options: ScanOptions(minimumFileSize: 0)).scan(path: (url ?? home).path)
    }

    private func recommend(
        tree: ScanTree? = nil,
        running: Set<String> = [],
        home homeURL: URL? = nil
    ) throws -> [CleanupSuggestion] {
        let scanTree: ScanTree
        if let tree {
            scanTree = tree
        } else {
            scanTree = try scan()
        }
        let root = homeURL ?? home!
        let environment = CleanupEnvironment(
            homePath: root.path,
            now: now,
            runningBundleIdentifiers: running
        )
        return CleanupAdvisor.recommend(tree: scanTree, environment: environment)
    }

    private func suggestions(_ ruleID: String, in suggestions: [CleanupSuggestion]) -> [CleanupSuggestion] {
        suggestions.filter { $0.ruleID == ruleID }
    }

    // MARK: - Catalog

    func testCatalogHasUniqueIDsAndExamples() {
        let ids = CleanupCatalog.rules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.count, 15)

        for rule in CleanupCatalog.rules {
            XCTAssertFalse(rule.title.isEmpty)
            XCTAssertFalse(rule.explanation.isEmpty)
            XCTAssertTrue(rule.examplePath.hasPrefix("~/"), "Unexpected example: \(rule.examplePath)")
        }
    }

    func testEnvironmentNormalizesHomePath() {
        let environment = CleanupEnvironment(homePath: "\(home.path)/")
        XCTAssertEqual(environment.homePath, home.path)
    }

    // MARK: - Rules

    func testAdvisorFindsAllRulesOnFixture() throws {
        try makeHomeFixture()
        let results = try recommend()

        XCTAssertNotNil(suggestions("trash", in: results).first)
        XCTAssertNotNil(suggestions("xcode-derived-data", in: results).first)
        XCTAssertNotNil(suggestions("xcode-archives", in: results).first)
        XCTAssertNotNil(suggestions("xcode-device-support", in: results).first)
        XCTAssertNotNil(suggestions("library-caches", in: results).first)
        XCTAssertNotNil(suggestions("ios-backups", in: results).first)
        XCTAssertNotNil(suggestions("docker-disk-image", in: results).first)
        XCTAssertNotNil(suggestions("gradle-cache", in: results).first)
        XCTAssertNotNil(suggestions("maven-cache", in: results).first)
        XCTAssertNotNil(suggestions("npm-cache", in: results).first)
        XCTAssertNotNil(suggestions("homebrew-cache", in: results).first)
        XCTAssertNotNil(suggestions("core-simulator-caches", in: results).first)
        XCTAssertNotNil(suggestions("xcode-user-data", in: results).first)
        XCTAssertNotNil(suggestions("node-modules", in: results).first)

        let installers = suggestions("downloads-installers", in: results)
        XCTAssertEqual(installers.count, 1)
        XCTAssertEqual(installers.first?.name, "old.dmg")

        let caches = suggestions("library-caches", in: results)
        XCTAssertEqual(caches.count, 1)
        XCTAssertEqual(caches.first?.name, "com.example.app")
        XCTAssertGreaterThanOrEqual(caches.first?.size ?? 0, 50 * 1024 * 1024)
    }

    func testRiskAndDefaultSelection() throws {
        try makeHomeFixture()
        let results = try recommend()

        let trash = try XCTUnwrap(suggestions("trash", in: results).first)
        XCTAssertEqual(trash.risk, .safe)
        XCTAssertEqual(trash.disposition, .deletePermanently)
        XCTAssertTrue(trash.isSelectedByDefault)

        let backups = try XCTUnwrap(suggestions("ios-backups", in: results).first)
        XCTAssertEqual(backups.risk, .review)
        XCTAssertFalse(backups.isSelectedByDefault)

        let userData = try XCTUnwrap(suggestions("xcode-user-data", in: results).first)
        XCTAssertEqual(userData.risk, .expert)
        XCTAssertFalse(userData.isSelectedByDefault)

        let nodeModules = try XCTUnwrap(suggestions("node-modules", in: results).first)
        XCTAssertEqual(nodeModules.risk, .expert)
        XCTAssertFalse(nodeModules.isSelectedByDefault)
    }

    func testDockerIsSkippedWhileRunning() throws {
        try makeHomeFixture()
        XCTAssertNotNil(suggestions("docker-disk-image", in: try recommend()).first)
        let running = try recommend(running: ["com.docker.docker"])
        XCTAssertNil(suggestions("docker-disk-image", in: running).first)
    }

    func testRulesDoNotFireOutsideScanRoot() throws {
        try makeHomeFixture()
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let tree = try scan(downloads)
        let results = try recommend(tree: tree)

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.path.hasPrefix(downloads.path) })
        XCTAssertTrue(results.allSatisfy { $0.ruleID == "downloads-installers" })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "old.dmg")
    }

    func testPackagesAreNotDescendedInto() throws {
        try makeHomeFixture()
        let results = try recommend()

        XCTAssertFalse(results.contains { $0.path.contains(".app/") })
        let nodeModules = suggestions("node-modules", in: results)
        XCTAssertEqual(nodeModules.count, 1)
        XCTAssertTrue(nodeModules[0].path.hasSuffix("Projects/app/node_modules"))
    }

    func testNestedSuggestionsAreDeduplicated() throws {
        try makeHomeFixture()
        try writeFile("Library/Caches/Shared/blob.bin", bytes: 51 * 1024 * 1024)
        try writeFile("Library/Caches/Shared/node_modules/pkg/index.js", bytes: 2048)

        let results = try recommend()
        XCTAssertTrue(suggestions("library-caches", in: results).contains { $0.name == "Shared" })
        XCTAssertFalse(results.contains { $0.path.hasSuffix("Library/Caches/Shared/node_modules") })
    }

    func testSuggestionsAreUniqueAndInsideHome() throws {
        try makeHomeFixture()
        let results = try recommend()

        let paths = results.map(\.path)
        XCTAssertEqual(Set(paths).count, paths.count)
        XCTAssertTrue(paths.allSatisfy { $0.hasPrefix(home.path) })
        XCTAssertTrue(results.allSatisfy { $0.relativePath.isEmpty == false })
    }

    func testLimitReturnsRequestedCount() throws {
        try makeHomeFixture()
        let tree = try scan()
        let environment = CleanupEnvironment(homePath: home.path, now: now)
        XCTAssertEqual(
            CleanupAdvisor.recommend(tree: tree, environment: environment, limit: 3).count,
            3
        )
        XCTAssertTrue(
            CleanupAdvisor.recommend(tree: tree, environment: environment, limit: 0).isEmpty
        )
    }
}
