import Foundation

public struct ScanHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public let rootPath: String
    public let rootName: String
    public let totalSize: Int64
    public let fileCount: Int
    public let folderCount: Int
    public let folderSizes: [String: Int64]

    public init(
        id: UUID = UUID(),
        date: Date,
        rootPath: String,
        rootName: String,
        totalSize: Int64,
        fileCount: Int,
        folderCount: Int,
        folderSizes: [String: Int64]
    ) {
        self.id = id
        self.date = date
        self.rootPath = rootPath
        self.rootName = rootName
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.folderSizes = folderSizes
    }

    public static func make(tree: ScanTree, date: Date = Date()) -> ScanHistoryEntry {
        let rootRaw = tree.name(of: 0)
        let rootName = rootRaw.isEmpty
            ? (tree.rootPath == "/" ? "Macintosh HD" : (tree.rootPath as NSString).lastPathComponent)
            : rootRaw
        return ScanHistoryEntry(
            date: date,
            rootPath: tree.rootPath,
            rootName: rootName,
            totalSize: tree.totalSize,
            fileCount: tree.totalFiles,
            folderCount: tree.directoryCount(),
            folderSizes: folderSizes(in: tree)
        )
    }

    static func folderSizes(in tree: ScanTree) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for child in tree.children(of: 0) {
            let node = tree.node(child)
            guard node.nodeKind.isContainer else { continue }
            let name = tree.name(of: child)
            guard !name.isEmpty else { continue }
            sizes[name] = node.size
        }
        return sizes
    }
}

public struct HistoryChange: Identifiable, Sendable {
    public let path: String
    public let before: Int64
    public let after: Int64

    public var delta: Int64 { after - before }
    public var id: String { path }

    public init(path: String, before: Int64, after: Int64) {
        self.path = path
        self.before = before
        self.after = after
    }
}

public struct HistoryDiff: Sendable {
    public let before: ScanHistoryEntry
    public let hasCurrent: Bool
    public let comparable: Bool
    public let totalAfter: Int64?
    public let fileCountAfter: Int?
    public let folderCountAfter: Int?
    public let changes: [HistoryChange]

    public var totalDelta: Int64? {
        totalAfter.map { $0 - before.totalSize }
    }

    public var fileCountDelta: Int? {
        fileCountAfter.map { $0 - before.fileCount }
    }

    public var comparableChanges: [HistoryChange] {
        guard comparable else { return [] }
        return changes.filter { $0.delta != 0 }
    }
}

public enum ScanHistoryDiff {
    public static func make(entry: ScanHistoryEntry, tree: ScanTree?) -> HistoryDiff {
        guard let tree else {
            return HistoryDiff(
                before: entry,
                hasCurrent: false,
                comparable: false,
                totalAfter: nil,
                fileCountAfter: nil,
                folderCountAfter: nil,
                changes: []
            )
        }
        let after = ScanHistoryEntry.folderSizes(in: tree)
        let keys = Set(entry.folderSizes.keys).union(after.keys)
        let changes = keys.map { key in
            HistoryChange(
                path: key,
                before: entry.folderSizes[key] ?? 0,
                after: after[key] ?? 0
            )
        }
        .sorted {
            if $0.delta.magnitude != $1.delta.magnitude {
                return $0.delta.magnitude > $1.delta.magnitude
            }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        return HistoryDiff(
            before: entry,
            hasCurrent: true,
            comparable: tree.rootPath == entry.rootPath,
            totalAfter: tree.totalSize,
            fileCountAfter: tree.totalFiles,
            folderCountAfter: tree.directoryCount(),
            changes: changes
        )
    }
}

public final class ScanHistoryStore {
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("DiskScope", isDirectory: true)
            .appendingPathComponent("scan-history.json")
    }

    private let url: URL

    public init(url: URL = ScanHistoryStore.defaultURL) {
        self.url = url
    }

    public func load() -> [ScanHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ScanHistoryEntry].self, from: data)) ?? []
    }

    public func save(_ entries: [ScanHistoryEntry]) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
