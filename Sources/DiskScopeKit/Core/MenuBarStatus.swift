import Foundation

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case free
    case percent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .free: return "Свободно"
        case .percent: return "Процент"
        }
    }
}

public struct MenuBarStatus: Sendable {
    public let freeBytes: Int64
    public let totalBytes: Int64
    public let purgeableBytes: Int64

    public init(freeBytes: Int64, totalBytes: Int64, purgeableBytes: Int64) {
        self.freeBytes = max(freeBytes, 0)
        self.totalBytes = max(totalBytes, 0)
        self.purgeableBytes = max(purgeableBytes, 0)
    }

    public init(volume: VolumeInfo) {
        self.init(
            freeBytes: volume.freeBytes,
            totalBytes: volume.totalBytes,
            purgeableBytes: volume.purgeableBytes
        )
    }

    public var usedBytes: Int64 { max(totalBytes - freeBytes, 0) }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    public func title(_ mode: MenuBarDisplayMode) -> String {
        switch mode {
        case .free: return ByteFormat.string(freeBytes)
        case .percent: return ByteFormat.percent(freeBytes, of: totalBytes)
        }
    }

    public func accessibilityLabel(_ mode: MenuBarDisplayMode) -> String {
        "DiskScope, \(title(mode)), \(ByteFormat.string(freeBytes)) free"
    }
}
