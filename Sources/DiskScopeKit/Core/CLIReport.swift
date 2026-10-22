import Foundation

public struct CLIBudget: Codable, Sendable {
    public let limitBytes: Int64
    public let withinBudget: Bool
    public let exceededBy: Int64

    public init(limitBytes: Int64, totalBytes: Int64) {
        self.limitBytes = limitBytes
        let over = max(totalBytes - limitBytes, 0)
        self.exceededBy = over
        self.withinBudget = over == 0
    }
}

public struct CLIEntry: Codable, Sendable {
    public let name: String
    public let path: String
    public let relativePath: String
    public let bytes: Int64
    public let human: String
    public let isDirectory: Bool

    public init(name: String, path: String, relativePath: String, bytes: Int64, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.relativePath = relativePath
        self.bytes = bytes
        self.human = ByteFormat.string(bytes)
        self.isDirectory = isDirectory
    }
}

/// Machine-readable output for `diskscope-cli --json`.
public struct CLIReport: Codable, Sendable {
    public let schemaVersion: Int
    public let path: String
    public let totalBytes: Int64
    public let totalHuman: String
    public let files: Int
    public let folders: Int
    public let nodes: Int
    public let durationSeconds: Double
    public let scanner: String
    public let skippedItems: Int
    public let skippedMounts: Int
    public let hardLinkBytes: Int64
    public let budget: CLIBudget?
    public let topLevel: [CLIEntry]
    public let largest: [CLIEntry]

    public init(
        path: String,
        totalBytes: Int64,
        files: Int,
        folders: Int,
        nodes: Int,
        durationSeconds: Double,
        scanner: String,
        skippedItems: Int,
        skippedMounts: Int,
        hardLinkBytes: Int64,
        budget: CLIBudget?,
        topLevel: [CLIEntry],
        largest: [CLIEntry]
    ) {
        self.schemaVersion = 1
        self.path = path
        self.totalBytes = totalBytes
        self.totalHuman = ByteFormat.string(totalBytes)
        self.files = files
        self.folders = folders
        self.nodes = nodes
        self.durationSeconds = durationSeconds
        self.scanner = scanner
        self.skippedItems = skippedItems
        self.skippedMounts = skippedMounts
        self.hardLinkBytes = hardLinkBytes
        self.budget = budget
        self.topLevel = topLevel
        self.largest = largest
    }

    public static func make(tree: ScanTree, budgetBytes: Int64?, limit: Int) -> CLIReport {
        let top = tree.children(of: 0)
            .sorted { tree.node($0).size > tree.node($1).size }
            .prefix(max(limit, 0))
            .map { index -> CLIEntry in
                let node = tree.node(index)
                let raw = tree.name(of: index)
                let name = raw.isEmpty ? "Small files" : raw
                return CLIEntry(
                    name: name,
                    path: tree.path(of: index),
                    relativePath: tree.relativePath(of: index),
                    bytes: node.size,
                    isDirectory: node.nodeKind.isContainer
                )
            }
        let largest = tree.largestItems(limit: max(limit, 0)).map { index -> CLIEntry in
            let node = tree.node(index)
            let raw = tree.name(of: index)
            return CLIEntry(
                name: raw.isEmpty ? "Small files" : raw,
                path: tree.path(of: index),
                relativePath: tree.relativePath(of: index),
                bytes: node.size,
                isDirectory: node.nodeKind.isContainer
            )
        }
        return CLIReport(
            path: tree.rootPath,
            totalBytes: tree.totalSize,
            files: tree.totalFiles,
            folders: tree.directoryCount(),
            nodes: tree.count,
            durationSeconds: tree.report.duration,
            scanner: tree.report.usedBulkScanner ? "getattrlistbulk" : "readdir",
            skippedItems: tree.report.skippedItems,
            skippedMounts: tree.report.skippedMounts,
            hardLinkBytes: tree.report.hardLinkBytes,
            budget: budgetBytes.map { CLIBudget(limitBytes: $0, totalBytes: tree.totalSize) },
            topLevel: Array(top),
            largest: largest
        )
    }

    public func encoded(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

public enum ByteSize {
    /// Parses `1048576`, `10MB`, `1.5 GB` using decimal units.
    public static func parse(_ value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let suffixes: [(String, Double)] = [
            ("tb", 1_000_000_000_000),
            ("gb", 1_000_000_000),
            ("mb", 1_000_000),
            ("kb", 1_000),
            ("b", 1),
        ]
        var number = trimmed
        var multiplier = 1.0
        for (suffix, factor) in suffixes where trimmed.hasSuffix(suffix) {
            number = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            multiplier = factor
            break
        }
        guard let parsed = Double(number.replacingOccurrences(of: ",", with: ".")),
              parsed.isFinite, parsed >= 0 else {
            return nil
        }
        let bytes = parsed * multiplier
        guard bytes <= Double(Int64.max) else { return nil }
        return Int64(bytes.rounded())
    }
}
