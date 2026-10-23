import Foundation

/// Kind of a node in the scan tree.
public enum NodeKind: UInt8, Sendable {
    case directory = 0
    case file = 1
    case symlink = 2
    /// A directory that behaves like a single item (.app, .photoslibrary, ...).
    case package = 3
    /// Synthetic node collecting many small files of one directory.
    case aggregate = 4

    public var isContainer: Bool { self == .directory || self == .package }
    public var isAggregate: Bool { self == .aggregate }
}

/// Compact in-memory representation of a file or folder.
/// Names live in a shared byte blob, nodes reference it by offset, which keeps
/// the footprint of a multi-million item scan low.
public struct ScanNode: Sendable, Codable {
    public var nameOffset: Int32 = 0
    public var nameLength: Int32 = 0
    public var parent: Int32 = -1
    public var childrenStart: Int32 = 0
    public var childrenCount: Int32 = 0
    /// For containers: number of files contained (recursively).
    /// For files: 1. For aggregates: number of aggregated files.
    public var itemCount: Int32 = 0
    /// Allocated size on disk in bytes, aggregated for containers.
    public var size: Int64 = 0
    public var kind: UInt8 = NodeKind.file.rawValue
    /// Dominant file category of the subtree (used to colour folders).
    public var dominant: UInt8 = UInt8(FileCategory.other.rawValue)

    /// Creation day as a day number since 2001-01-01 UTC, or `unknownDay`.
    public var createdDays: Int32 = ScanNode.unknownDay
    /// Last modification day as a day number since 2001-01-01 UTC, or `unknownDay`.
    public var modifiedDays: Int32 = ScanNode.unknownDay

    /// Sentinel for entries whose timestamps were not returned by the filesystem.
    public static let unknownDay = Int32.min

    private static let referenceEpoch: Int64 = 978_307_200
    private static let secondsPerDay: Int64 = 86_400

    /// Converts Unix seconds to a day number, flooring dates before 2001.
    static func dayNumber(seconds: Int64) -> Int32 {
        let day = Int64(floor((Double(seconds) - Double(referenceEpoch)) / Double(secondsPerDay)))
        guard day > Int64(Int32.min), day < Int64(Int32.max) else { return unknownDay }
        return Int32(day)
    }

    /// Creation timestamp where zero means the filesystem did not provide one.
    static func creationDay(seconds: Int64) -> Int32 {
        seconds > 0 ? dayNumber(seconds: seconds) : unknownDay
    }

    /// Noon UTC of the given day: stable when formatted in any local timezone.
    static func date(day: Int32) -> Date? {
        guard day != unknownDay else { return nil }
        let seconds = referenceEpoch + Int64(day) * secondsPerDay + 43_200
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func earlierDay(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        if lhs == unknownDay { return rhs }
        if rhs == unknownDay { return lhs }
        return min(lhs, rhs)
    }

    static func laterDay(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        if lhs == unknownDay { return rhs }
        if rhs == unknownDay { return lhs }
        return max(lhs, rhs)
    }

    public var nodeKind: NodeKind {
        get { NodeKind(rawValue: kind & 0x7F) ?? .file }
        set { kind = (kind & 0x80) | newValue.rawValue }
    }

    /// True for a hard link whose blocks were already counted under another path.
    public var isHardLink: Bool {
        get { kind & 0x80 != 0 }
        set { kind = (kind & 0x7F) | (newValue ? 0x80 : 0) }
    }

    public var category: FileCategory {
        get { FileCategory(rawValue: Int(dominant)) ?? .other }
        set { dominant = UInt8(newValue.rawValue) }
    }
}

/// Summary produced by a scan.
public struct ScanReport: Sendable, Codable {
    public var duration: TimeInterval = 0
    public var entriesRead: Int = 0
    public var bytesFound: Int64 = 0
    /// Folders that could not be opened (usually TCC / permission errors).
    public var skippedItems: Int = 0
    /// Mount points that were intentionally not descended into.
    public var skippedMounts: Int = 0
    public var sampleSkippedPaths: [String] = []
    public var usedBulkScanner: Bool = true
    /// Bytes that were not counted again because another hard link owns them.
    public var hardLinkBytes: Int64 = 0

    public init(
        duration: TimeInterval = 0,
        entriesRead: Int = 0,
        bytesFound: Int64 = 0,
        skippedItems: Int = 0,
        skippedMounts: Int = 0,
        sampleSkippedPaths: [String] = [],
        usedBulkScanner: Bool = true,
        hardLinkBytes: Int64 = 0
    ) {
        self.duration = duration
        self.entriesRead = entriesRead
        self.bytesFound = bytesFound
        self.skippedItems = skippedItems
        self.skippedMounts = skippedMounts
        self.sampleSkippedPaths = sampleSkippedPaths
        self.usedBulkScanner = usedBulkScanner
        self.hardLinkBytes = hardLinkBytes
    }
}

public struct CategoryStat: Identifiable, Sendable {
    public let category: FileCategory
    public let size: Int64
    public let count: Int
    public var id: Int { category.rawValue }
}

/// Result of pruning subtrees from a scan tree.
///
/// `groups` describe exactly what was removed, so the same removal can be
/// undone later without rescanning the disk.
public struct ScanTreeRemoval {
    public struct Group: Sendable {
        /// Top-level removed node.
        public let root: Int32
        /// Every node newly marked as deleted by this group (root + descendants).
        public let marked: [Int32]
        public let bytes: Int64
        public let files: Int
    }

    public let tree: ScanTree
    public let bytes: Int64
    public let files: Int
    public let groups: [Group]
}

/// Immutable (except for pruning after deletions) scan result.
public final class ScanTree {
    public private(set) var nodes: [ScanNode]
    private(set) var names: [UInt8]
    private(set) var deleted: [Bool]
    public let rootPath: String
    public let report: ScanReport

    public init(nodes: [ScanNode], names: [UInt8], rootPath: String, report: ScanReport) {
        self.nodes = nodes
        self.names = names
        self.rootPath = rootPath
        self.report = report
        self.deleted = [Bool](repeating: false, count: nodes.count)
    }

    private init(nodes: [ScanNode], names: [UInt8], rootPath: String, report: ScanReport, deleted: [Bool]) {
        self.nodes = nodes
        self.names = names
        self.rootPath = rootPath
        self.report = report
        self.deleted = deleted
    }

    public var count: Int { nodes.count }
    public var rootIndex: Int32 { 0 }
    public var totalSize: Int64 { nodes[0].size }
    public var totalFiles: Int { Int(nodes[0].itemCount) }

    public func node(_ index: Int32) -> ScanNode { nodes[Int(index)] }

    public func isDeleted(_ index: Int32) -> Bool { deleted[Int(index)] }

    /// Finds a node by absolute path, following the scan root.
    public func index(ofPath path: String) -> Int32? {
        let root = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().path
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard target == root || target.hasPrefix(root == "/" ? "/" : root + "/") else {
            return nil
        }
        if target == root { return 0 }
        let relative = String(target.dropFirst(root == "/" ? 1 : root.count + 1))
        var index: Int32 = 0
        for component in relative.split(separator: "/") {
            guard let child = children(of: index).first(where: { name(of: $0) == component }) else {
                return nil
            }
            index = child
        }
        return index
    }

    public func name(of index: Int32) -> String {
        guard index >= 0, Int(index) < nodes.count else { return "" }
        let node = nodes[Int(index)]
        guard node.nameLength > 0 else { return "" }
        let start = Int(node.nameOffset)
        let end = start + Int(node.nameLength)
        guard start >= 0, end <= names.count else { return "" }
        return String(decoding: names[start..<end], as: UTF8.self)
    }

    public func fileExtension(of index: Int32) -> String {
        let name = name(of: index)
        guard let dot = name.lastIndex(of: "."), dot < name.index(before: name.endIndex) else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// Creation day as a day number since 2001-01-01 UTC, or `nil` when unknown.
    public func createdDay(of index: Int32) -> Int32? {
        guard index >= 0, Int(index) < nodes.count else { return nil }
        let day = nodes[Int(index)].createdDays
        return day == ScanNode.unknownDay ? nil : day
    }

    /// Last modification day as a day number since 2001-01-01 UTC, or `nil` when unknown.
    public func modifiedDay(of index: Int32) -> Int32? {
        guard index >= 0, Int(index) < nodes.count else { return nil }
        let day = nodes[Int(index)].modifiedDays
        return day == ScanNode.unknownDay ? nil : day
    }

    /// Creation date at noon UTC (day precision), or `nil` when unknown.
    public func created(of index: Int32) -> Date? {
        createdDay(of: index).flatMap { ScanNode.date(day: $0) }
    }

    /// Last modification date at noon UTC (day precision), or `nil` when unknown.
    public func modified(of index: Int32) -> Date? {
        modifiedDay(of: index).flatMap { ScanNode.date(day: $0) }
    }

    public func category(of index: Int32) -> FileCategory {
        let node = nodes[Int(index)]
        switch node.nodeKind {
        case .package:
            return .app
        case .aggregate:
            return .other
        case .directory:
            return node.category
        case .file, .symlink:
            let ext = fileExtension(of: index)
            if ext == "app" { return .app }
            return FileCategory.forExtension(ext)
        }
    }

    public func isDirectory(_ index: Int32) -> Bool {
        node(index).nodeKind.isContainer
    }

    /// All currently present children of a container.
    public func children(of index: Int32) -> [Int32] {
        let node = nodes[Int(index)]
        guard node.nodeKind.isContainer, node.childrenCount > 0 else { return [] }
        let start = Int(node.childrenStart)
        let end = start + Int(node.childrenCount)
        guard start >= 0, end <= nodes.count else { return [] }
        var result: [Int32] = []
        result.reserveCapacity(end - start)
        for i in start..<end where !deleted[i] {
            result.append(Int32(i))
        }
        return result
    }

    public func childCount(of index: Int32) -> Int {
        Int(nodes[Int(index)].childrenCount)
    }

    /// Path relative to the scan root (empty for the root itself).
    public func relativePath(of index: Int32) -> String {
        guard index > 0 else { return "" }
        var components: [String] = []
        var cursor = Int32(index)
        while cursor > 0 {
            components.append(name(of: cursor))
            cursor = nodes[Int(cursor)].parent
            if components.count > 512 { break }
        }
        return components.reversed().joined(separator: "/")
    }

    public func path(of index: Int32) -> String {
        guard index > 0 else { return rootPath }
        let relative = relativePath(of: index)
        if rootPath == "/" { return "/" + relative }
        return rootPath + "/" + relative
    }

    public func url(of index: Int32) -> URL {
        URL(fileURLWithPath: path(of: index))
    }

    public func parent(of index: Int32) -> Int32? {
        let p = nodes[Int(index)].parent
        return p >= 0 ? p : nil
    }

    // MARK: - Removal (after moving items to the trash)

    /// Returns a new immutable tree with the given subtrees pruned. The current
    /// tree is not mutated, so background statistics never race with deletions.
    public func removingSubtrees(at indices: [Int32]) -> ScanTreeRemoval {
        let copy = ScanTree(
            nodes: nodes,
            names: names,
            rootPath: rootPath,
            report: report,
            deleted: deleted
        )
        let removed = copy.removeSubtreesInPlace(at: indices)
        return ScanTreeRemoval(
            tree: copy,
            bytes: removed.bytes,
            files: removed.files,
            groups: removed.groups
        )
    }

    /// Returns a new tree with the given removal groups restored. Groups must be
    /// undone in reverse order of removal; this keeps earlier deletions intact.
    public func restoringSubtrees(groups: [ScanTreeRemoval.Group]) -> ScanTree {
        let copy = ScanTree(
            nodes: nodes,
            names: names,
            rootPath: rootPath,
            report: report,
            deleted: deleted
        )
        copy.restoreGroupsInPlace(groups)
        return copy
    }

    @discardableResult
    private func removeSubtreesInPlace(
        at indices: [Int32]
    ) -> (bytes: Int64, files: Int, groups: [ScanTreeRemoval.Group]) {
        var totalBytes: Int64 = 0
        var totalFiles = 0
        var groups: [ScanTreeRemoval.Group] = []
        for index in indices {
            guard index > 0, Int(index) < nodes.count, !deleted[Int(index)] else { continue }
            if hasDeletedAncestor(index) { continue }

            // The size of a container already includes its whole subtree.
            let removedBytes = nodes[Int(index)].size
            var stack = [Int32(index)]
            var marked: [Int32] = []
            var files = 0
            while let current = stack.popLast() {
                let i = Int(current)
                if deleted[i] { continue }
                deleted[i] = true
                marked.append(current)
                if !nodes[i].nodeKind.isContainer {
                    files += Int(nodes[i].itemCount)
                }
                if nodes[i].nodeKind.isContainer, nodes[i].childrenCount > 0 {
                    let start = Int(nodes[i].childrenStart)
                    let end = start + Int(nodes[i].childrenCount)
                    for child in start..<end { stack.append(Int32(child)) }
                }
            }

            var parent = nodes[Int(index)].parent
            while parent >= 0 {
                nodes[Int(parent)].size -= removedBytes
                nodes[Int(parent)].itemCount -= Int32(files)
                parent = nodes[Int(parent)].parent
            }
            groups.append(ScanTreeRemoval.Group(
                root: index,
                marked: marked,
                bytes: removedBytes,
                files: files
            ))
            totalBytes += removedBytes
            totalFiles += files
        }
        return (totalBytes, totalFiles, groups)
    }

    private func restoreGroupsInPlace(_ groups: [ScanTreeRemoval.Group]) {
        for group in groups {
            let root = Int(group.root)
            guard root > 0, root < nodes.count, deleted[root] else { continue }
            deleted[root] = false
            for index in group.marked {
                let i = Int(index)
                guard i > 0, i < nodes.count, deleted[i] else { continue }
                deleted[i] = false
            }

            // The root size already excludes descendants deleted by earlier,
            // still-pending removals, so adding it up the chain is exact.
            let bytes = nodes[root].size
            let items = nodes[root].itemCount
            var parent = nodes[root].parent
            while parent >= 0 {
                nodes[Int(parent)].size += bytes
                nodes[Int(parent)].itemCount += items
                parent = nodes[Int(parent)].parent
            }
        }
    }

    private func hasDeletedAncestor(_ index: Int32) -> Bool {
        var cursor = nodes[Int(index)].parent
        while cursor >= 0 {
            if deleted[Int(cursor)] { return true }
            cursor = nodes[Int(cursor)].parent
        }
        return false
    }

    // MARK: - Statistics

    /// Largest files and application packages, skipping the contents of packages
    /// (a .app is shown as one item, its dylibs are not offered for cleanup).
    public func largestItems(limit: Int = 3000) -> [Int32] {
        var result: [Int32] = []
        var stack: [Int32] = [0]
        while let index = stack.popLast() {
            let node = nodes[Int(index)]
            if deleted[Int(index)] { continue }
            switch node.nodeKind {
            case .package:
                result.append(index)
            case .file:
                result.append(index)
            case .directory:
                if node.childrenCount > 0 {
                    let start = Int(node.childrenStart)
                    let end = start + Int(node.childrenCount)
                    for child in start..<end { stack.append(Int32(child)) }
                }
            case .symlink, .aggregate:
                break
            }
        }
        result.sort { nodes[Int($0)].size > nodes[Int($1)].size }
        if result.count > limit { result.removeLast(result.count - limit) }
        return result
    }

    public func categoryStats() -> [CategoryStat] {
        var sizes = [Int64](repeating: 0, count: FileCategory.allCases.count)
        var counts = [Int](repeating: 0, count: FileCategory.allCases.count)
        var stack: [Int32] = [0]
        while let index = stack.popLast() {
            let i = Int(index)
            if deleted[i] { continue }
            let node = nodes[i]
            switch node.nodeKind {
            case .package:
                let category = FileCategory.app
                sizes[category.rawValue] += node.size
                counts[category.rawValue] += 1
            case .file:
                let category = FileCategory.forExtension(fileExtension(of: index))
                sizes[category.rawValue] += node.size
                counts[category.rawValue] += 1
            case .aggregate:
                sizes[FileCategory.other.rawValue] += node.size
                counts[FileCategory.other.rawValue] += Int(node.itemCount)
            case .directory:
                if node.childrenCount > 0 {
                    let start = Int(node.childrenStart)
                    let end = start + Int(node.childrenCount)
                    for child in start..<end { stack.append(Int32(child)) }
                }
            case .symlink:
                break
            }
        }
        return FileCategory.allCases
            .map { CategoryStat(category: $0, size: sizes[$0.rawValue], count: counts[$0.rawValue]) }
            .filter { $0.size > 0 || $0.count > 0 }
            .sorted { $0.size > $1.size }
    }

    public func directoryCount() -> Int {
        guard nodes.count < 4_000_000 else {
            return nodes.reduce(into: 0) { partial, node in
                if node.nodeKind.isContainer { partial += 1 }
            }
        }
        var count = 0
        for i in 0..<nodes.count where !deleted[i] {
            if nodes[i].nodeKind.isContainer { count += 1 }
        }
        return count
    }
}
