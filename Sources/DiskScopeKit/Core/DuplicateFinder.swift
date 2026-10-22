import CryptoKit
import Foundation

public struct DuplicateFile: Identifiable, Hashable, Sendable {
    public let index: Int32
    public let path: String
    public let relativePath: String
    public let modified: Date?

    public var id: Int32 { index }

    public init(index: Int32, path: String, relativePath: String, modified: Date?) {
        self.index = index
        self.path = path
        self.relativePath = relativePath
        self.modified = modified
    }
}

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let size: Int64
    public let files: [DuplicateFile]

    public var wastedBytes: Int64 {
        guard files.count > 1 else { return 0 }
        return size * Int64(files.count - 1)
    }

    public init(id: String, size: Int64, files: [DuplicateFile]) {
        self.id = id
        self.size = size
        self.files = files
    }
}

public struct DuplicateOptions: Sendable {
    public var minimumSize: Int64
    public var partialBytes: Int
    public var maxGroups: Int

    public init(minimumSize: Int64 = 1_000_000, partialBytes: Int = 64 * 1024, maxGroups: Int = 300) {
        self.minimumSize = max(minimumSize, 0)
        self.partialBytes = max(partialBytes, 1)
        self.maxGroups = max(maxGroups, 1)
    }
}

public struct DuplicateResult: Sendable {
    public let groups: [DuplicateGroup]
    public let totalWasted: Int64
    public let candidateCount: Int
    public let hashedCount: Int
    public let truncated: Bool
    public let cancelled: Bool

    public init(
        groups: [DuplicateGroup],
        totalWasted: Int64,
        candidateCount: Int,
        hashedCount: Int,
        truncated: Bool,
        cancelled: Bool
    ) {
        self.groups = groups
        self.totalWasted = totalWasted
        self.candidateCount = candidateCount
        self.hashedCount = hashedCount
        self.truncated = truncated
        self.cancelled = cancelled
    }

    public static let empty = DuplicateResult(
        groups: [],
        totalWasted: 0,
        candidateCount: 0,
        hashedCount: 0,
        truncated: false,
        cancelled: false
    )
}

public enum DuplicateFinder {
    private struct HashKey: Hashable {
        let size: Int64
        let hash: String
    }

    public static func find(
        tree: ScanTree,
        options: DuplicateOptions = DuplicateOptions(),
        progress: ((Double) -> Void)? = nil,
        isCancelled: (() -> Bool)? = nil
    ) -> DuplicateResult {
        let candidates = collectCandidates(tree: tree, options: options)
        guard !candidates.isEmpty else { return .empty }

        let sizeGroups = Dictionary(grouping: candidates) { tree.node($0).size }
            .filter { $0.value.count > 1 }
        let candidateCount = sizeGroups.values.reduce(0) { $0 + $1.count }
        guard candidateCount > 0 else { return .empty }

        var partialGroups: [HashKey: [Int32]] = [:]
        var processed = 0
        for (size, indices) in sizeGroups {
            for index in indices {
                if isCancelled?() == true {
                    return DuplicateResult(
                        groups: [], totalWasted: 0, candidateCount: candidateCount,
                        hashedCount: processed, truncated: false, cancelled: true
                    )
                }
                guard let hash = digest(
                    url: tree.url(of: index),
                    limit: options.partialBytes,
                    isCancelled: isCancelled
                ) else { continue }
                partialGroups[HashKey(size: size, hash: hash), default: []].append(index)
                processed += 1
                progress?(0.4 * Double(processed) / Double(candidateCount))
            }
        }

        let partialMatches = partialGroups.filter { $0.value.count > 1 }
        let fullTotal = partialMatches.values.reduce(0) { $0 + $1.count }
        guard fullTotal > 0 else {
            progress?(1)
            return DuplicateResult(
                groups: [], totalWasted: 0, candidateCount: candidateCount,
                hashedCount: processed, truncated: false, cancelled: false
            )
        }

        var fullGroups: [HashKey: [Int32]] = [:]
        var fullProcessed = 0
        for (key, indices) in partialMatches {
            for index in indices {
                if isCancelled?() == true {
                    return DuplicateResult(
                        groups: [], totalWasted: 0, candidateCount: candidateCount,
                        hashedCount: processed, truncated: false, cancelled: true
                    )
                }
                guard let hash = digest(
                    url: tree.url(of: index),
                    limit: nil,
                    isCancelled: isCancelled
                ) else { continue }
                fullGroups[HashKey(size: key.size, hash: hash), default: []].append(index)
                fullProcessed += 1
                progress?(0.4 + 0.6 * Double(fullProcessed) / Double(fullTotal))
            }
        }

        var groups: [DuplicateGroup] = []
        for (key, indices) in fullGroups where indices.count > 1 {
            let files = indices.map { index in
                DuplicateFile(
                    index: index,
                    path: tree.path(of: index),
                    relativePath: tree.relativePath(of: index),
                    modified: tree.modified(of: index)
                )
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            groups.append(DuplicateGroup(
                id: "\(key.size):\(key.hash)",
                size: key.size,
                files: files
            ))
        }

        groups.sort {
            if $0.wastedBytes != $1.wastedBytes { return $0.wastedBytes > $1.wastedBytes }
            return $0.size > $1.size
        }
        let totalWasted = groups.reduce(0) { $0 + $1.wastedBytes }
        let truncated = groups.count > options.maxGroups
        if truncated {
            groups = Array(groups.prefix(options.maxGroups))
        }
        progress?(1)
        return DuplicateResult(
            groups: groups,
            totalWasted: totalWasted,
            candidateCount: candidateCount,
            hashedCount: processed,
            truncated: truncated,
            cancelled: false
        )
    }

    private static func collectCandidates(tree: ScanTree, options: DuplicateOptions) -> [Int32] {
        var result: [Int32] = []
        var stack: [Int32] = [0]
        while let index = stack.popLast() {
            let node = tree.node(index)
            switch node.nodeKind {
            case .directory:
                for child in tree.children(of: index) { stack.append(child) }
            case .package, .aggregate, .symlink:
                continue
            case .file:
                guard node.size >= options.minimumSize, !node.isHardLink else { continue }
                result.append(index)
            }
        }
        return result
    }

    private static func digest(
        url: URL,
        limit: Int?,
        isCancelled: (() -> Bool)?
    ) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit
        while true {
            if isCancelled?() == true { return nil }
            let chunkSize = min(1 << 20, remaining ?? (1 << 20))
            guard chunkSize > 0 else { break }
            guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else { break }
            hasher.update(data: data)
            if let current = remaining {
                remaining = current - data.count
                if remaining ?? 0 <= 0 { break }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
