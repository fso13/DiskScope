import Foundation

/// A mounted volume as shown in the sidebar.
public struct VolumeInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let totalBytes: Int64
    public let freeBytes: Int64
    /// Capacity macOS can make available by evicting purgeable data.
    public let importantFreeBytes: Int64
    public let isInternal: Bool
    public let isRemovable: Bool

    public var usedBytes: Int64 { max(totalBytes - freeBytes, 0) }
    public var purgeableBytes: Int64 { max(importantFreeBytes - freeBytes, 0) }
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }
    public var url: URL { URL(fileURLWithPath: path) }

    public init(
        id: String,
        name: String,
        path: String,
        totalBytes: Int64,
        freeBytes: Int64,
        importantFreeBytes: Int64? = nil,
        isInternal: Bool,
        isRemovable: Bool
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.importantFreeBytes = max(importantFreeBytes ?? freeBytes, freeBytes)
        self.isInternal = isInternal
        self.isRemovable = isRemovable
    }

    public static func loadAll() -> [VolumeInfo] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsBrowsableKey,
            .volumeIsReadOnlyKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            guard values.volumeIsBrowsable != false, values.volumeIsReadOnly != true else { continue }
            guard let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity else { continue }
            let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(free)
            let path = url.path
            if path.hasPrefix("/System/Volumes") { continue }
            let name = values.volumeName ?? (path == "/" ? "Macintosh HD" : url.lastPathComponent)
            volumes.append(VolumeInfo(
                id: path,
                name: name,
                path: path,
                totalBytes: Int64(total),
                freeBytes: Int64(free),
                importantFreeBytes: important,
                isInternal: values.volumeIsInternal ?? false,
                isRemovable: values.volumeIsRemovable ?? false
            ))
        }

        if !volumes.contains(where: { $0.path == "/" }) {
            var stats = statfs()
            if statfs("/", &stats) == 0 {
                let total = Int64(stats.f_bsize) * Int64(stats.f_blocks)
                let free = Int64(stats.f_bsize) * Int64(stats.f_bavail)
                volumes.append(VolumeInfo(
                    id: "/",
                    name: "Macintosh HD",
                    path: "/",
                    totalBytes: total,
                    freeBytes: free,
                    isInternal: true,
                    isRemovable: false
                ))
            }
        }

        return volumes.sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func freeSpace(at path: String) -> (total: Int64, free: Int64)? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        return (Int64(stats.f_bsize) * Int64(stats.f_blocks), Int64(stats.f_bsize) * Int64(stats.f_bavail))
    }
}
