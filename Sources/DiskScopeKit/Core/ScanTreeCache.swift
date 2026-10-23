import Foundation
import CoreServices

public struct ScanTreeSnapshot: Codable, Sendable {
    public let nodes: [ScanNode]
    public let names: [UInt8]
    public let rootPath: String
    public let report: ScanReport

    public init(tree: ScanTree) {
        self.nodes = tree.nodes
        self.names = tree.names
        self.rootPath = tree.rootPath
        self.report = tree.report
    }

    public func tree() -> ScanTree {
        ScanTree(nodes: nodes, names: names, rootPath: rootPath, report: report)
    }
}

public struct ScanCacheMetadata: Codable, Sendable {
    public let formatVersion: Int
    public let appVersion: String
    public let build: String
    public let rootPath: String
    public let volumeUUID: String
    public let minimumFileSize: Int64
    public let treatsPackagesAsSingleItems: Bool
    public let excludedPaths: [String]
    public let eventID: UInt64
    public let savedAt: Date
}

public struct ScanTreeCacheEntry: Codable, Sendable {
    public final class TreeBox: Codable, @unchecked Sendable {
        public let snapshot: ScanTreeSnapshot
        init(snapshot: ScanTreeSnapshot) { self.snapshot = snapshot }
    }

    public let metadata: ScanCacheMetadata
    public let tree: TreeBox
}

public final class ScanTreeCache: @unchecked Sendable {
    public static let shared = ScanTreeCache()
    public static let formatVersion = 1

    private let url: URL
    private let lock = NSLock()

    public init(url: URL = ScanTreeCache.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("DiskScope", isDirectory: true)
            .appendingPathComponent("scan-cache.plist")
    }

    public func load() -> ScanTreeCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = PropertyListDecoder()
        return try? decoder.decode(ScanTreeCacheEntry.self, from: data)
    }

    public func save(
        tree: ScanTree,
        options: ScanOptions,
        eventID: UInt64,
        appVersion: String = ScanTreeCache.currentVersion,
        build: String = ScanTreeCache.currentBuild
    ) {
        let metadata = ScanCacheMetadata(
            formatVersion: Self.formatVersion,
            appVersion: appVersion,
            build: build,
            rootPath: tree.rootPath,
            volumeUUID: Self.volumeUUID(for: tree.rootPath),
            minimumFileSize: options.minimumFileSize,
            treatsPackagesAsSingleItems: options.treatsPackagesAsSingleItems,
            excludedPaths: options.excludedPaths,
            eventID: eventID,
            savedAt: Date()
        )
        let entry = ScanTreeCacheEntry(
            metadata: metadata,
            tree: ScanTreeCacheEntry.TreeBox(snapshot: ScanTreeSnapshot(tree: tree))
        )
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(entry).write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    /// Returns a cached tree only when metadata matches and FSEvents reports no changes.
    public func reusableTree(
        rootPath: String,
        options: ScanOptions,
        appVersion: String = ScanTreeCache.currentVersion,
        build: String = ScanTreeCache.currentBuild
    ) -> ScanTree? {
        guard let entry = load() else { return nil }
        guard Self.compatible(
            metadata: entry.metadata,
            rootPath: rootPath,
            options: options,
            appVersion: appVersion,
            build: build
        ) else { return nil }
        let current = FSEventsHistory.currentEventID()
        guard current >= entry.metadata.eventID else { return nil }
        guard let changes = FSEventsHistory.changes(since: entry.metadata.eventID, path: rootPath) else {
            return nil
        }
        let tree = entry.tree.snapshot.tree()
        for change in changes where !Self.isBenign(change: change, tree: tree) {
            return nil
        }
        return tree
    }

    public static func compatible(
        metadata: ScanCacheMetadata,
        rootPath: String,
        options: ScanOptions,
        appVersion: String,
        build: String
    ) -> Bool {
        metadata.formatVersion == formatVersion
            && metadata.rootPath == rootPath
            && metadata.appVersion == appVersion
            && metadata.build == build
            && metadata.volumeUUID == volumeUUID(for: rootPath)
            && metadata.minimumFileSize == options.minimumFileSize
            && metadata.treatsPackagesAsSingleItems == options.treatsPackagesAsSingleItems
            && metadata.excludedPaths == options.excludedPaths
    }

    private static func isBenign(change: FSEventChange, tree: ScanTree) -> Bool {
        let cacheDirectory = ScanTreeCache.defaultURL.deletingLastPathComponent().path
        if change.path.hasPrefix(cacheDirectory) { return true }
        let flags = Int(change.flags)
        let invalidating = Int(kFSEventStreamEventFlagMustScanSubDirs)
            | Int(kFSEventStreamEventFlagUserDropped)
            | Int(kFSEventStreamEventFlagKernelDropped)
            | Int(kFSEventStreamEventFlagRootChanged)
            | Int(kFSEventStreamEventFlagEventIdsWrapped)
            | Int(kFSEventStreamEventFlagItemRemoved)
            | Int(kFSEventStreamEventFlagItemRenamed)
        if flags & invalidating != 0 { return false }

        guard flags & Int(kFSEventStreamEventFlagItemCreated) != 0 else { return false }
        guard let index = tree.index(ofPath: change.path) else { return false }
        let node = tree.node(index)
        if flags & Int(kFSEventStreamEventFlagItemModified) == 0 { return true }
        if node.nodeKind.isContainer { return true }

        var info = stat()
        guard lstat(change.path, &info) == 0 else { return false }
        let size = Int64(info.st_blocks) * 512
        let day = ScanNode.dayNumber(seconds: Int64(info.st_mtimespec.tv_sec))
        return size == node.size && day == node.modifiedDays
    }

    public static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    public static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    static func volumeUUID(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey])
        return values?.volumeUUIDString ?? path
    }
}

public struct FSEventChange: Sendable {
    public let path: String
    public let flags: FSEventStreamEventFlags

    public init(path: String, flags: FSEventStreamEventFlags) {
        self.path = path
        self.flags = flags
    }
}

public enum FSEventsHistory {
    public static func currentEventID() -> UInt64 {
        FSEventsGetCurrentEventId()
    }

    /// Returns changed paths, or `nil` when event history is unavailable.
    public static func changedPaths(since eventID: UInt64, path: String = "/") -> [String]? {
        changes(since: eventID, path: path)?.map(\.path)
    }

    public static func changes(since eventID: UInt64, path: String = "/") -> [FSEventChange]? {
        let box = EventBox(since: eventID)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            fseventsCallback,
            &context,
            [path] as CFArray,
            eventID,
            0.1,
            flags
        ) else {
            return nil
        }
        let queue = DispatchQueue(label: "ru.diskscope.fsevents.cache")
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        _ = box.semaphore.wait(timeout: .now() + 0.6)
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        return box.paths
    }
}

private final class EventBox {
    let semaphore = DispatchSemaphore(value: 0)
    let since: FSEventStreamEventId
    var paths: [FSEventChange] = []

    init(since: FSEventStreamEventId) {
        self.since = since
    }
}

private let fseventsCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, flags, eventIds in
    guard let info else { return }
    let box = Unmanaged<EventBox>.fromOpaque(info).takeUnretainedValue()
    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
    for offset in 0..<numEvents {
        let eventID = eventIds[offset]
        guard eventID > box.since, offset < paths.count else { continue }
        box.paths.append(FSEventChange(path: paths[offset], flags: flags[offset]))
    }
    box.semaphore.signal()
}
