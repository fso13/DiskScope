import Foundation

public struct StaleOptions: Sendable {
    public var months: Int
    public var minimumSize: Int64
    public var now: Date
    public var limit: Int

    public init(
        months: Int = 12,
        minimumSize: Int64 = 10_000_000,
        now: Date = Date(),
        limit: Int = 20
    ) {
        self.months = max(months, 1)
        self.minimumSize = max(minimumSize, 0)
        self.now = now
        self.limit = max(limit, 1)
    }
}

public struct StaleFile: Identifiable, Sendable {
    public let index: Int32
    public let name: String
    public let path: String
    public let relativePath: String
    public let size: Int64
    public let modified: Date?
    public let ageDays: Int

    public var id: Int32 { index }

    public init(
        index: Int32,
        name: String,
        path: String,
        relativePath: String,
        size: Int64,
        modified: Date?,
        ageDays: Int
    ) {
        self.index = index
        self.name = name
        self.path = path
        self.relativePath = relativePath
        self.size = size
        self.modified = modified
        self.ageDays = ageDays
    }
}

public struct StaleResult: Sendable {
    public let files: [StaleFile]
    public let totalFiles: Int
    public let totalBytes: Int64
    public let months: Int
    public let minimumSize: Int64

    public var truncated: Bool { totalFiles > files.count }

    public init(
        files: [StaleFile],
        totalFiles: Int,
        totalBytes: Int64,
        months: Int,
        minimumSize: Int64
    ) {
        self.files = files
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.months = months
        self.minimumSize = minimumSize
    }

    public static let empty = StaleResult(files: [], totalFiles: 0, totalBytes: 0, months: 12, minimumSize: 0)
}

public enum StaleFiles {
    static let systemPrefixes = [
        "/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/dev",
        "/Applications", "/cores", "/Volumes",
    ]
    static let ignoredComponents: Set<String> = [
        ".git", "node_modules", "Pods", ".build", "DerivedData", "Carthage",
        ".venv", "venv", "__pycache__", ".gradle", ".idea", ".next", "target",
    ]
    static let ignoredExtensions: Set<String> = [
        "framework", "dylib", "a", "o", "swiftmodule", "xcframework",
    ]

    public static func find(tree: ScanTree, options: StaleOptions = StaleOptions()) -> StaleResult {
        let today = ScanNode.dayNumber(seconds: Int64(options.now.timeIntervalSince1970))
        let cutoff = today - Int32(options.months * 30)
        var matches: [StaleFile] = []
        var totalBytes: Int64 = 0

        for index in 1..<Int32(tree.count) {
            let node = tree.node(index)
            guard node.nodeKind == .file,
                  !node.isHardLink,
                  node.size >= options.minimumSize,
                  let modifiedDay = tree.modifiedDay(of: index),
                  modifiedDay <= cutoff else { continue }
            guard let modified = tree.modified(of: index) else { continue }
            let path = tree.path(of: index)
            guard !isExcluded(path: path, tree: tree, index: index) else { continue }
            let relative = tree.relativePath(of: index)
            totalBytes += node.size
            matches.append(StaleFile(
                index: index,
                name: tree.name(of: index),
                path: path,
                relativePath: relative,
                size: node.size,
                modified: modified,
                ageDays: Int(today) - Int(modifiedDay)
            ))
        }

        matches.sort {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        return StaleResult(
            files: Array(matches.prefix(options.limit)),
            totalFiles: matches.count,
            totalBytes: totalBytes,
            months: options.months,
            minimumSize: options.minimumSize
        )
    }

    static func isExcluded(path: String, tree: ScanTree, index: Int32) -> Bool {
        for prefix in systemPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return true
        }
        let components = path.split(separator: "/").map(String.init)
        if components.contains(where: { ignoredComponents.contains($0) }) {
            return true
        }
        if ignoredExtensions.contains((path as NSString).pathExtension.lowercased()) {
            return true
        }
        var parent = tree.node(index).parent
        while parent >= 0 {
            let kind = tree.node(parent).nodeKind
            if kind == .package { return true }
            if kind == .symlink { return true }
            parent = tree.node(parent).parent
        }
        return false
    }
}
