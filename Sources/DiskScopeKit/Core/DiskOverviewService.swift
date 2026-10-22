import Foundation

public struct APFSSnapshot: Identifiable, Hashable, Sendable {
    public let name: String
    public let date: Date?

    public var id: String { name }

    public init(name: String, date: Date?) {
        self.name = name
        self.date = date
    }
}

public struct TrashSummary: Sendable {
    public let size: Int64
    public let items: Int
    public let url: URL

    public init(size: Int64, items: Int, url: URL) {
        self.size = size
        self.items = items
        self.url = url
    }

    public static func empty(url: URL) -> TrashSummary {
        TrashSummary(size: 0, items: 0, url: url)
    }
}

public struct DiskOverview: Sendable {
    public let volume: VolumeInfo
    public let purgeableBytes: Int64
    public let trash: TrashSummary
    public let snapshots: [APFSSnapshot]
    public let snapshotsAvailable: Bool
    public let updatedAt: Date

    public var totalBytes: Int64 { volume.totalBytes }
    public var freeBytes: Int64 { volume.freeBytes }
    public var usedBytes: Int64 { volume.usedBytes }
    public var usedFraction: Double { volume.usedFraction }

    public init(
        volume: VolumeInfo,
        purgeableBytes: Int64,
        trash: TrashSummary,
        snapshots: [APFSSnapshot],
        snapshotsAvailable: Bool = true,
        updatedAt: Date
    ) {
        self.volume = volume
        self.purgeableBytes = max(purgeableBytes, 0)
        self.trash = trash
        self.snapshots = snapshots
        self.snapshotsAvailable = snapshotsAvailable
        self.updatedAt = updatedAt
    }
}

public enum DiskOverviewService {
    public static func load(
        volume: VolumeInfo,
        trashURL: URL? = nil,
        snapshotOutput: String? = nil,
        now: Date = Date()
    ) -> DiskOverview {
        let trash = scanTrash(at: trashURL ?? defaultTrashURL)
        let snapshots: [APFSSnapshot]
        let available: Bool
        if let snapshotOutput {
            snapshots = parseSnapshots(snapshotOutput)
            available = true
        } else {
            let result = listSnapshots()
            snapshots = result.snapshots
            available = result.available
        }
        return DiskOverview(
            volume: volume,
            purgeableBytes: volume.purgeableBytes,
            trash: trash,
            snapshots: snapshots,
            snapshotsAvailable: available,
            updatedAt: now
        )
    }

    public static var defaultTrashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
    }

    public static func scanTrash(at url: URL) -> TrashSummary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty(url: url)
        }
        guard let tree = try? DiskScanner(options: .detailed).scan(path: url.path) else {
            return .empty(url: url)
        }
        return TrashSummary(
            size: tree.totalSize,
            items: tree.children(of: 0).count,
            url: url
        )
    }

    public static func listSnapshots() -> (snapshots: [APFSSnapshot], available: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ([], false)
        }
        guard process.terminationStatus == 0 else { return ([], false) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (parseSnapshots(String(bytes: data, encoding: .utf8) ?? ""), true)
    }

    public static func parseSnapshots(_ output: String) -> [APFSSnapshot] {
        let regex = try? NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})-(\d{6})"#)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        var snapshots: [APFSSnapshot] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("Snapshots for") else { continue }
            guard let regex,
                  let match = regex.firstMatch(
                      in: line,
                      range: NSRange(line.startIndex..., in: line)
                  ),
                  let range = Range(match.range, in: line),
                  let date = formatter.date(from: String(line[range])) else {
                continue
            }
            snapshots.append(APFSSnapshot(name: line, date: date))
        }
        return snapshots.sorted {
            switch ($0.date, $1.date) {
            case let (left?, right?): return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return $0.name < $1.name
            }
        }
    }
}
