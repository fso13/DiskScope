import Foundation

public struct ScanOptions: Sendable {
    /// Files smaller than this are aggregated per directory instead of becoming
    /// individual nodes. Keeps memory flat on multi-million file volumes while
    /// preserving exact total sizes.
    public var minimumFileSize: Int64
    /// Treat .app / .photoslibrary / ... as single items in the UI.
    public var treatsPackagesAsSingleItems: Bool

    public init(minimumFileSize: Int64 = 64 * 1024, treatsPackagesAsSingleItems: Bool = true) {
        self.minimumFileSize = minimumFileSize
        self.treatsPackagesAsSingleItems = treatsPackagesAsSingleItems
    }

    public static let balanced = ScanOptions()
    public static let detailed = ScanOptions(minimumFileSize: 0)
}

public struct ScanProgress: Sendable {
    public var entries: Int
    public var files: Int
    public var directories: Int
    public var bytes: Int64
    public var currentPath: String
    public var elapsed: TimeInterval

    public init(
        entries: Int = 0,
        files: Int = 0,
        directories: Int = 0,
        bytes: Int64 = 0,
        currentPath: String = "",
        elapsed: TimeInterval = 0
    ) {
        self.entries = entries
        self.files = files
        self.directories = directories
        self.bytes = bytes
        self.currentPath = currentPath
        self.elapsed = elapsed
    }

    public var entriesPerSecond: Double {
        elapsed > 0 ? Double(entries) / elapsed : 0
    }
}

public enum ScanError: Error, LocalizedError {
    case cancelled
    case notDirectory(String)
    case cannotOpen(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Сканирование отменено"
        case .notDirectory(let path):
            return "«\(path)» не является папкой"
        case .cannotOpen(let path, let code):
            return "Не удалось открыть «\(path)»: \(String(cString: strerror(code)))"
        }
    }
}

public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    public init() {}

    public func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

// Attribute bit masks (sys/attr.h) and vnode types (sys/vnode.h).
private let attrBitMapCount: UInt16 = 5
private let attrCMNReturnedAttrs: UInt32 = 0x8000_0000
private let attrCMNName: UInt32 = 0x0000_0001
private let attrCMNObjType: UInt32 = 0x0000_0008
private let attrCMNCRTime: UInt32 = 0x0000_0200
private let attrCMNModTime: UInt32 = 0x0000_0400
private let attrCMNFileID: UInt32 = 0x0200_0000
private let attrDirMountStatus: UInt32 = 0x0000_0004
private let attrDirAllocSize: UInt32 = 0x0000_0008
private let attrFileAllocSize: UInt32 = 0x0000_0004
private let mntStatusMountPoint: UInt32 = 0x0000_0001
private let mntStatusTrigger: UInt32 = 0x0000_0002
private let vTypeRegular: UInt32 = 1
private let vTypeDirectory: UInt32 = 2
private let vTypeSymlink: UInt32 = 5

/// Scans a directory tree and produces a compact `ScanTree`.
public final class DiskScanner {
    public let options: ScanOptions

    public init(options: ScanOptions = ScanOptions()) {
        self.options = options
    }

    public func scan(
        path: String,
        cancellation: ScanCancellation? = nil,
        progress: ((ScanProgress) -> Void)? = nil
    ) throws -> ScanTree {
        let standardized = Self.standardized(path: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ScanError.notDirectory(standardized)
        }

        let useBulk = supportsBulk(at: standardized)

        let fd = open(standardized, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else {
            throw ScanError.cannotOpen(standardized, errno)
        }
        defer { close(fd) }

        var rootStat = stat()
        _ = fstat(fd, &rootStat)
        let rootSize = Int64(rootStat.st_blocks) * 512
        let rootCreatedDays = ScanNode.creationDay(seconds: Int64(rootStat.st_birthtimespec.tv_sec))
        let rootModifiedDays = ScanNode.dayNumber(seconds: Int64(rootStat.st_mtimespec.tv_sec))

        let rootName: String
        if standardized == "/" {
            rootName = "Macintosh HD"
        } else {
            rootName = URL(fileURLWithPath: standardized).lastPathComponent
        }

        let session = ScanSession(
            builder: TreeBuilder(
                rootName: rootName,
                rootSize: rootSize,
                rootCreatedDays: rootCreatedDays,
                rootModifiedDays: rootModifiedDays
            ),
            rootPath: standardized,
            rootDevice: rootStat.st_dev,
            minimumFileSize: options.minimumFileSize,
            treatsPackagesAsSingleItems: options.treatsPackagesAsSingleItems,
            cancellation: cancellation,
            progress: progress
        )
        session.usedBulkScanner = useBulk
        session.start()

        try scanDirectory(fd: fd, nodeIndex: 0, session: session, useBulk: useBulk)

        let report = session.makeReport()
        return session.builder.finalize(rootPath: standardized, report: report)
    }

    private static func standardized(path: String) -> String {
        var expanded = (path as NSString).expandingTildeInPath
        if expanded.count > 1, expanded.hasSuffix("/") {
            expanded.removeLast()
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func makeAttributeList() -> attrlist {
        var attributes = attrlist()
        attributes.bitmapcount = attrBitMapCount
        attributes.commonattr = attrCMNReturnedAttrs | attrCMNName | attrCMNObjType
            | attrCMNCRTime | attrCMNModTime | attrCMNFileID
        attributes.dirattr = attrDirMountStatus | attrDirAllocSize
        attributes.fileattr = attrFileAllocSize
        return attributes
    }

    private func supportsBulk(at path: String) -> Bool {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return true }
        defer { close(fd) }
        var attributes = makeAttributeList()
        let bufferSize = 16 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        let result = getattrlistbulk(fd, &attributes, buffer, bufferSize, 0)
        if result < 0 {
            let code = errno
            return !(code == ENOTSUP || code == EINVAL)
        }
        return true
    }

    // MARK: - Directory walking

    private func scanDirectory(fd: Int32, nodeIndex: Int32, session: ScanSession, useBulk: Bool) throws {
        var subdirectories: [Subdirectory] = []
        var aggregateBytes: Int64 = 0
        var aggregateCount = 0
        var aggregateCreatedDays = ScanNode.unknownDay
        var aggregateModifiedDays = ScanNode.unknownDay

        func process(
            _ name: UnsafePointer<UInt8>,
            _ nameLength: Int,
            _ kind: NodeKind,
            _ size: Int64,
            _ mountStatus: UInt32,
            _ createdDays: Int32,
            _ modifiedDays: Int32,
            _ fileID: UInt64
        ) {
            if mountStatus & (mntStatusMountPoint | mntStatusTrigger) != 0 {
                session.skippedMounts += 1
                return
            }

            var countedSize = size
            switch kind {
            case .directory:
                let isPackage = session.isPackage(name, length: nameLength)
                let index = session.builder.appendNode(
                    parent: nodeIndex,
                    name: name,
                    nameLength: nameLength,
                    kind: isPackage ? .package : .directory,
                    size: size,
                    itemCount: 0,
                    category: isPackage ? .app : .other,
                    createdDays: createdDays,
                    modifiedDays: modifiedDays
                )
                subdirectories.append(Subdirectory(name: name, length: nameLength, node: index))
                session.directories += 1
            case .file:
                let duplicate = fileID != 0 && !session.registerFileID(fileID)
                if duplicate {
                    countedSize = 0
                    session.hardLinkBytes += size
                }
                if size >= session.minimumFileSize {
                    let category = FileCategory.forExtension(session.extensionString(name, length: nameLength))
                    _ = session.builder.appendNode(
                        parent: nodeIndex,
                        name: name,
                        nameLength: nameLength,
                        kind: .file,
                        size: countedSize,
                        itemCount: 1,
                        category: category,
                        createdDays: createdDays,
                        modifiedDays: modifiedDays,
                        isHardLink: duplicate
                    )
                } else {
                    aggregateBytes += countedSize
                    aggregateCount += 1
                    aggregateCreatedDays = ScanNode.earlierDay(aggregateCreatedDays, createdDays)
                    aggregateModifiedDays = ScanNode.laterDay(aggregateModifiedDays, modifiedDays)
                }
                session.files += 1
            case .symlink:
                _ = session.builder.appendNode(
                    parent: nodeIndex,
                    name: name,
                    nameLength: nameLength,
                    kind: .symlink,
                    size: size,
                    itemCount: 1,
                    category: .other,
                    createdDays: createdDays,
                    modifiedDays: modifiedDays
                )
                session.files += 1
            default:
                break
            }
            session.entries += 1
            session.bytes += countedSize
            session.tick()
        }

        if useBulk {
            try readBulk(fd: fd, session: session, handler: process)
        } else {
            try readReaddir(fd: fd, session: session, handler: process)
        }

        if aggregateCount > 0 {
            _ = session.builder.appendNode(
                parent: nodeIndex,
                name: nil,
                nameLength: 0,
                kind: .aggregate,
                size: aggregateBytes,
                itemCount: Int32(aggregateCount),
                category: .other,
                createdDays: aggregateCreatedDays,
                modifiedDays: aggregateModifiedDays
            )
        }

        for subdirectory in subdirectories {
            session.components.append(subdirectory.displayName)
            let childFD = subdirectory.withCString { name in
                openat(fd, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            if childFD >= 0 {
                do {
                    try scanDirectory(fd: childFD, nodeIndex: subdirectory.node, session: session, useBulk: useBulk)
                    close(childFD)
                } catch {
                    close(childFD)
                    throw error
                }
            } else {
                session.recordSkipped(path: session.currentPath(), errno: errno)
            }
            session.components.removeLast()
        }
    }

    // MARK: - getattrlistbulk

    private func readBulk(
        fd: Int32,
        session: ScanSession,
        handler: (UnsafePointer<UInt8>, Int, NodeKind, Int64, UInt32, Int32, Int32, UInt64) -> Void
    ) throws {
        var attributes = makeAttributeList()
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        while true {
            if session.isCancelled { throw ScanError.cancelled }
            let count = getattrlistbulk(fd, &attributes, buffer, bufferSize, 0)
            if count < 0 {
                let code = errno
                if code == EINTR { continue }
                session.recordSkipped(path: session.currentPath(), errno: code)
                break
            }
            if count == 0 { break }

            var offset = 0
            for _ in 0..<count {
                let base = UnsafeRawPointer(buffer + offset)
                let entryLength = Int(base.loadUnaligned(as: UInt32.self))
                guard entryLength >= 36, offset + entryLength <= bufferSize else { break }

                let returnedCommon = base.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
                let returnedDirectory = base.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
                let returnedFile = base.loadUnaligned(fromByteOffset: 16, as: UInt32.self)

                if returnedCommon & attrCMNName != 0, returnedCommon & attrCMNObjType != 0 {
                    let referenceOffset = 24
                    let dataOffset = Int(base.loadUnaligned(fromByteOffset: referenceOffset, as: Int32.self))
                    let nameLength = Int(base.loadUnaligned(fromByteOffset: referenceOffset + 4, as: UInt32.self))
                    let objectType = base.loadUnaligned(fromByteOffset: 32, as: UInt32.self)
                    let namePointer = base.advanced(by: referenceOffset + dataOffset).assumingMemoryBound(to: UInt8.self)
                    var effectiveLength = nameLength
                    if effectiveLength > 0, namePointer[effectiveLength - 1] == 0 { effectiveLength -= 1 }

                    if effectiveLength > 0, referenceOffset + dataOffset + effectiveLength <= entryLength {
                        var cursor = 36
                        var createdDays = ScanNode.unknownDay
                        var modifiedDays = ScanNode.unknownDay
                        if returnedCommon & attrCMNCRTime != 0 {
                            if cursor + 16 <= entryLength {
                                let seconds = base.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
                                createdDays = ScanNode.creationDay(seconds: seconds)
                            }
                            cursor += 16
                        }
                        if returnedCommon & attrCMNModTime != 0 {
                            if cursor + 16 <= entryLength {
                                let seconds = base.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
                                modifiedDays = ScanNode.dayNumber(seconds: seconds)
                            }
                            cursor += 16
                        }

                        var fileID: UInt64 = 0
                        if returnedCommon & attrCMNFileID != 0 {
                            if cursor + 8 <= entryLength {
                                fileID = base.loadUnaligned(fromByteOffset: cursor, as: UInt64.self)
                            }
                            cursor += 8
                        }

                        var size: Int64 = 0
                        var mountStatus: UInt32 = 0
                        if objectType == vTypeDirectory {
                            if returnedDirectory & attrDirMountStatus != 0 {
                                mountStatus = base.loadUnaligned(fromByteOffset: cursor, as: UInt32.self)
                                cursor += 4
                            }
                            if returnedDirectory & attrDirAllocSize != 0 {
                                size = base.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
                            }
                            handler(
                                namePointer, effectiveLength, .directory, size, mountStatus,
                                createdDays, modifiedDays, 0
                            )
                        } else if objectType == vTypeRegular {
                            if returnedFile & attrFileAllocSize != 0 {
                                size = base.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
                            }
                            handler(
                                namePointer, effectiveLength, .file, size, 0,
                                createdDays, modifiedDays, fileID
                            )
                        } else if objectType == vTypeSymlink {
                            handler(
                                namePointer, effectiveLength, .symlink, 0, 0,
                                createdDays, modifiedDays, 0
                            )
                        }
                    }
                }

                offset += entryLength
            }
        }
    }

    // MARK: - readdir fallback

    private func readReaddir(
        fd: Int32,
        session: ScanSession,
        handler: (UnsafePointer<UInt8>, Int, NodeKind, Int64, UInt32, Int32, Int32, UInt64) -> Void
    ) throws {
        guard let directory = fdopendir(dup(fd)) else {
            session.recordSkipped(path: session.currentPath(), errno: errno)
            return
        }
        defer { closedir(directory) }
        let dirFD = dirfd(directory)

        while let entry = readdir(directory) {
            if session.isCancelled { throw ScanError.cancelled }
            var rawName = entry.pointee.d_name
            let nameCapacity = MemoryLayout.size(ofValue: rawName)
            withUnsafePointer(to: &rawName) { tuplePointer in
                tuplePointer.withMemoryRebound(to: UInt8.self, capacity: nameCapacity) { namePointer in
                    let length = Int(strlen(UnsafeRawPointer(namePointer).assumingMemoryBound(to: CChar.self)))
                    if length == 0 { return }
                    let isDotEntry = namePointer[0] == 46
                    if isDotEntry, length == 1 || (length == 2 && namePointer[1] == 46) { return }

                    var info = stat()
                    let statResult = namePointer.withMemoryRebound(to: CChar.self, capacity: length + 1) {
                        fstatat(dirFD, $0, &info, AT_SYMLINK_NOFOLLOW)
                    }
                    if statResult != 0 { return }

                    let type = info.st_mode & S_IFMT
                    let size = Int64(info.st_blocks) * 512
                    let isMount = info.st_dev != session.rootDevice
                    let createdDays = ScanNode.creationDay(seconds: Int64(info.st_birthtimespec.tv_sec))
                    let modifiedDays = ScanNode.dayNumber(seconds: Int64(info.st_mtimespec.tv_sec))
                    if type == S_IFDIR {
                        handler(
                            namePointer, length, .directory, size, isMount ? mntStatusMountPoint : 0,
                            createdDays, modifiedDays, 0
                        )
                    } else if type == S_IFREG {
                        handler(
                            namePointer, length, .file, size, 0,
                            createdDays, modifiedDays, UInt64(info.st_ino)
                        )
                    } else if type == S_IFLNK {
                        handler(namePointer, length, .symlink, size, 0, createdDays, modifiedDays, 0)
                    }
                }
            }
        }
    }
}

// MARK: - Session state

private final class Subdirectory {
    let bytes: [UInt8]
    let node: Int32
    lazy var displayName = String(decoding: bytes.prefix(bytes.count - 1), as: UTF8.self)

    init(name: UnsafePointer<UInt8>, length: Int, node: Int32) {
        var storage = [UInt8](repeating: 0, count: length + 1)
        for index in 0..<length { storage[index] = name[index] }
        self.bytes = storage
        self.node = node
    }

    func withCString<T>(_ body: (UnsafePointer<CChar>) -> T) -> T {
        bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) { body($0) }
        }
    }
}

private final class ScanSession {
    let builder: TreeBuilder
    let rootPath: String
    let rootDevice: dev_t
    let minimumFileSize: Int64
    let treatsPackagesAsSingleItems: Bool
    let cancellation: ScanCancellation?
    let progress: ((ScanProgress) -> Void)?

    var entries = 0
    var files = 0
    var directories = 0
    var bytes: Int64 = 0
    var skippedItems = 0
    var skippedMounts = 0
    var sampleSkippedPaths: [String] = []
    var usedBulkScanner = true
    var hardLinkBytes: Int64 = 0
    var components: [String] = []

    private var seenFileIDs: Set<UInt64> = []

    private var startTime = Date()
    private var lastProgressTime = Date.distantPast
    private var ticksSinceProgress = 0

    init(
        builder: TreeBuilder,
        rootPath: String,
        rootDevice: dev_t,
        minimumFileSize: Int64,
        treatsPackagesAsSingleItems: Bool,
        cancellation: ScanCancellation?,
        progress: ((ScanProgress) -> Void)?
    ) {
        self.builder = builder
        self.rootPath = rootPath
        self.rootDevice = rootDevice
        self.minimumFileSize = minimumFileSize
        self.treatsPackagesAsSingleItems = treatsPackagesAsSingleItems
        self.cancellation = cancellation
        self.progress = progress
    }

    func start() {
        startTime = Date()
    }

    var isCancelled: Bool { cancellation?.isCancelled ?? false }

    func registerFileID(_ id: UInt64) -> Bool {
        seenFileIDs.insert(id).inserted
    }

    func tick() {
        ticksSinceProgress += 1
        guard ticksSinceProgress >= 2048 else { return }
        ticksSinceProgress = 0
        guard let progress else { return }
        let now = Date()
        guard now.timeIntervalSince(lastProgressTime) > 0.1 else { return }
        lastProgressTime = now
        let elapsed = now.timeIntervalSince(startTime)
        progress(ScanProgress(
            entries: entries,
            files: files,
            directories: directories,
            bytes: bytes,
            currentPath: currentPath(),
            elapsed: elapsed
        ))
    }

    func currentPath() -> String {
        if components.isEmpty { return rootPath }
        if rootPath == "/" { return "/" + components.joined(separator: "/") }
        return rootPath + "/" + components.joined(separator: "/")
    }

    func recordSkipped(path: String, errno code: Int32) {
        skippedItems += 1
        if sampleSkippedPaths.count < 25, !sampleSkippedPaths.contains(path) {
            sampleSkippedPaths.append(path)
        }
    }

    func isPackage(_ name: UnsafePointer<UInt8>, length: Int) -> Bool {
        guard treatsPackagesAsSingleItems, length > 4 else { return false }
        let suffixes = [".app", ".photoslibrary", ".fcpbundle", ".imovielibrary", ".musiclibrary", ".tvlibrary", ".logicx", ".band"]
        for suffix in suffixes where length > suffix.utf8.count {
            if matchesSuffix(name, length: length, suffix: suffix) { return true }
        }
        return false
    }

    private func matchesSuffix(_ name: UnsafePointer<UInt8>, length: Int, suffix: String) -> Bool {
        var index = length - suffix.utf8.count
        for byte in suffix.utf8 {
            let value = name[index]
            let lower = (value >= 65 && value <= 90) ? value + 32 : value
            if lower != byte { return false }
            index += 1
        }
        return true
    }

    func extensionString(_ name: UnsafePointer<UInt8>, length: Int) -> String {
        guard length > 1 else { return "" }
        var index = length - 1
        while index > 0 {
            if name[index] == 46 {
                if index == length - 1 { return "" }
                return String(decoding: UnsafeBufferPointer(start: name + index + 1, count: length - index - 1), as: UTF8.self)
            }
            index -= 1
        }
        return ""
    }

    func makeReport() -> ScanReport {
        ScanReport(
            duration: Date().timeIntervalSince(startTime),
            entriesRead: entries,
            bytesFound: bytes,
            skippedItems: skippedItems,
            skippedMounts: skippedMounts,
            sampleSkippedPaths: sampleSkippedPaths,
            usedBulkScanner: usedBulkScanner,
            hardLinkBytes: hardLinkBytes
        )
    }
}

// MARK: - Tree builder

final class TreeBuilder {
    private(set) var nodes: [ScanNode] = []
    private(set) var names: [UInt8] = []

    init(
        rootName: String,
        rootSize: Int64,
        rootCreatedDays: Int32 = ScanNode.unknownDay,
        rootModifiedDays: Int32 = ScanNode.unknownDay
    ) {
        var root = ScanNode()
        let bytes = Array(rootName.utf8)
        root.nameOffset = 0
        root.nameLength = Int32(bytes.count)
        root.kind = NodeKind.directory.rawValue
        root.size = rootSize
        root.category = .other
        root.createdDays = rootCreatedDays
        root.modifiedDays = rootModifiedDays
        names.append(contentsOf: bytes)
        nodes.append(root)
        names.reserveCapacity(4 << 20)
        nodes.reserveCapacity(1 << 18)
    }

    func appendNode(
        parent: Int32,
        name: UnsafePointer<UInt8>?,
        nameLength: Int,
        kind: NodeKind,
        size: Int64,
        itemCount: Int32,
        category: FileCategory,
        createdDays: Int32,
        modifiedDays: Int32,
        isHardLink: Bool = false
    ) -> Int32 {
        let index = Int32(nodes.count)
        var node = ScanNode()
        node.parent = parent
        node.nameOffset = Int32(names.count)
        node.nameLength = Int32(nameLength)
        node.kind = kind.rawValue
        node.isHardLink = isHardLink
        node.size = size
        node.itemCount = itemCount
        node.dominant = UInt8(category.rawValue)
        node.createdDays = createdDays
        node.modifiedDays = modifiedDays
        if let name, nameLength > 0 {
            names.append(contentsOf: UnsafeBufferPointer(start: name, count: nameLength))
        }
        if nodes[Int(parent)].childrenCount == 0 {
            nodes[Int(parent)].childrenStart = index
        }
        nodes[Int(parent)].childrenCount += 1
        nodes.append(node)
        return index
    }

    func finalize(rootPath: String, report: ScanReport) -> ScanTree {
        if nodes.count > 1 {
            var index = nodes.count - 1
            while index >= 1 {
                let parent = Int(nodes[index].parent)
                if parent >= 0 {
                    nodes[parent].size += nodes[index].size
                    nodes[parent].itemCount += nodes[index].itemCount
                }
                index -= 1
            }
        }

        if nodes.count > 1 {
            var index = nodes.count - 1
            while index >= 0 {
                let node = nodes[index]
                if node.nodeKind.isContainer {
                    var best: Int64 = -1
                    var bestCategory = FileCategory.other.rawValue
                    if node.childrenCount > 0 {
                        let start = Int(node.childrenStart)
                        let end = start + Int(node.childrenCount)
                        if start >= 0, end <= nodes.count {
                            for child in start..<end where nodes[child].size > best {
                                best = nodes[child].size
                                bestCategory = Int(nodes[child].dominant)
                            }
                        }
                    }
                    nodes[index].dominant = UInt8(bestCategory)
                }
                index -= 1
            }
        }
        return ScanTree(nodes: nodes, names: names, rootPath: rootPath, report: report)
    }
}
