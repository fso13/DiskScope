import Foundation

/// File families offered by the media search.
public enum MediaType: String, CaseIterable, Identifiable, Sendable {
    case image
    case audio
    case video
    case document
    case doc
    case pdf

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .image: return "Изображения"
        case .audio: return "Музыка"
        case .video: return "Видео"
        case .document: return "Документы"
        case .doc: return "DOC / DOCX"
        case .pdf: return "PDF"
        }
    }

    public var symbolName: String {
        switch self {
        case .image: return "photo.fill"
        case .audio: return "music.note"
        case .video: return "film.fill"
        case .document: return "doc.text.fill"
        case .doc: return "doc.fill"
        case .pdf: return "doc.richtext.fill"
        }
    }

    public var category: FileCategory {
        switch self {
        case .image: return .image
        case .audio: return .audio
        case .video: return .video
        case .document, .doc, .pdf: return .document
        }
    }

    public var fileExtensions: Set<String> {
        switch self {
        case .image: return Self.imageExtensions
        case .audio: return Self.audioExtensions
        case .video: return Self.videoExtensions
        case .document: return Self.documentExtensions
        case .doc: return Self.docExtensions
        case .pdf: return Self.pdfExtensions
        }
    }

    public func matches(_ fileExtension: String) -> Bool {
        fileExtensions.contains(fileExtension.lowercased())
    }

    /// Broad types selected by the "Все" shortcut. DOC and PDF are included
    /// in `.document`; the two narrow types are for targeted searches.
    public static let broad: Set<MediaType> = [.image, .audio, .video, .document]

    private static let imageExtensions = FileCategory.extensions(for: .image)
    private static let audioExtensions = FileCategory.extensions(for: .audio)
    private static let videoExtensions = FileCategory.extensions(for: .video)
    private static let docExtensions: Set<String> = ["doc", "docx"]
    private static let pdfExtensions: Set<String> = ["pdf"]

    /// Office/ebook/text documents. Deliberately excludes source and data
    /// files such as .json/.swift which FileCategory groups as documents.
    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "odt", "ods",
        "odp", "epub", "mobi", "txt", "csv", "tsv",
    ]
}

/// A concrete type used for display and icons. DOC and PDF get a more precise
/// label than the broad `.document` kind.
public enum MediaKind: String, CaseIterable, Identifiable, Sendable {
    case image
    case audio
    case video
    case document
    case doc
    case pdf

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .image: return "Изображение"
        case .audio: return "Музыка"
        case .video: return "Видео"
        case .document: return "Документ"
        case .doc: return "DOC"
        case .pdf: return "PDF"
        }
    }

    public var symbolName: String {
        switch self {
        case .image: return "photo.fill"
        case .audio: return "music.note"
        case .video: return "film.fill"
        case .document: return "doc.text.fill"
        case .doc: return "doc.fill"
        case .pdf: return "doc.richtext.fill"
        }
    }

    public var category: FileCategory {
        switch self {
        case .image: return .image
        case .audio: return .audio
        case .video: return .video
        case .document, .doc, .pdf: return .document
        }
    }

    public static func forExtension(_ fileExtension: String) -> MediaKind? {
        let ext = fileExtension.lowercased()
        if MediaType.pdf.matches(ext) { return .pdf }
        if MediaType.doc.matches(ext) { return .doc }
        if MediaType.image.matches(ext) { return .image }
        if MediaType.audio.matches(ext) { return .audio }
        if MediaType.video.matches(ext) { return .video }
        if MediaType.document.matches(ext) { return .document }
        return nil
    }
}

public struct MediaFile: Identifiable, Hashable, Sendable {
    public let path: String
    public let name: String
    public let relativePath: String
    public let sourceRoot: String
    public let size: Int64
    public let kind: MediaKind
    public let modified: Date?

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var fileExtension: String { (path as NSString).pathExtension.lowercased() }

    public init(
        path: String,
        name: String? = nil,
        relativePath: String = "",
        sourceRoot: String = "",
        size: Int64,
        kind: MediaKind,
        modified: Date? = nil
    ) {
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.relativePath = relativePath
        self.sourceRoot = sourceRoot
        self.size = size
        self.kind = kind
        self.modified = modified
    }

    public static func == (lhs: MediaFile, rhs: MediaFile) -> Bool { lhs.path == rhs.path }
    public func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

public struct MediaSearchOptions: Sendable {
    public var folders: [URL]
    public var types: Set<MediaType>
    public var maxResults: Int
    public var includeHidden: Bool

    public init(
        folders: [URL],
        types: Set<MediaType>,
        maxResults: Int = 25_000,
        includeHidden: Bool = false
    ) {
        self.folders = folders
        self.types = types
        self.maxResults = maxResults
        self.includeHidden = includeHidden
    }
}

public struct MediaSearchProgress: Sendable {
    public var scanned: Int
    public var matched: Int
    public var bytes: Int64
    public var currentPath: String
    public var elapsed: TimeInterval

    public init(
        scanned: Int = 0,
        matched: Int = 0,
        bytes: Int64 = 0,
        currentPath: String = "",
        elapsed: TimeInterval = 0
    ) {
        self.scanned = scanned
        self.matched = matched
        self.bytes = bytes
        self.currentPath = currentPath
        self.elapsed = elapsed
    }
}

public struct MediaSearchResult: Sendable {
    public let files: [MediaFile]
    public let skippedItems: Int
    public let duration: TimeInterval
    public let truncated: Bool

    public init(
        files: [MediaFile],
        skippedItems: Int,
        duration: TimeInterval,
        truncated: Bool
    ) {
        self.files = files
        self.skippedItems = skippedItems
        self.duration = duration
        self.truncated = truncated
    }

    public var totalBytes: Int64 {
        files.reduce(Int64(0)) { $0 + $1.size }
    }
}

public enum MediaSearchError: Error, LocalizedError {
    case cancelled
    case noFolders
    case noTypes
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Поиск отменён"
        case .noFolders:
            return "Добавьте хотя бы одну папку для поиска."
        case .noTypes:
            return "Выберите хотя бы один тип файлов."
        case .failed(let message):
            return message
        }
    }
}

/// Recursively finds media files by extension. It deliberately does not build
/// a scan tree: the user can search arbitrary folders, including folders that
/// were never scanned in the main window.
public final class MediaSearchEngine {
    public init() {}

    public func search(
        options: MediaSearchOptions,
        cancellation: ScanCancellation? = nil,
        progress: ((MediaSearchProgress) -> Void)? = nil
    ) throws -> MediaSearchResult {
        guard !options.types.isEmpty else { throw MediaSearchError.noTypes }
        guard !options.folders.isEmpty else { throw MediaSearchError.noFolders }

        let started = Date()
        let roots = Self.prunedRoots(options.folders)
        guard !roots.isEmpty else { throw MediaSearchError.noFolders }

        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        let keySet = Set(keys)

        var files: [MediaFile] = []
        var seen = Set<String>()
        var scanned = 0
        var skipped = 0
        var truncated = false
        var matchedBytes: Int64 = 0

        progress?(MediaSearchProgress(currentPath: "", elapsed: 0))

        outer: for root in roots {
            let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard rootValues?.isDirectory == true, rootValues?.isPackage != true else {
                skipped += 1
                continue
            }

            var enumeratorOptions: FileManager.DirectoryEnumerationOptions = [
                .skipsPackageDescendants,
            ]
            if !options.includeHidden {
                enumeratorOptions.insert(.skipsHiddenFiles)
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: enumeratorOptions,
                errorHandler: { _, _ in
                    skipped += 1
                    return true
                }
            ) else {
                skipped += 1
                continue
            }

            for case let url as URL in enumerator {
                if cancellation?.isCancelled == true {
                    throw MediaSearchError.cancelled
                }

                scanned += 1

                guard let values = try? url.resourceValues(forKeys: keySet),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      options.includeHidden || values.isHidden != true
                else {
                    continue
                }

                let ext = url.pathExtension.lowercased()
                guard let kind = MediaKind.forExtension(ext),
                      options.types.contains(where: { $0.matches(ext) })
                else {
                    continue
                }

                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }

                let size = Int64(values.fileSize ?? 0)
                let relative = Self.relativePath(of: path, under: root.path)
                files.append(
                    MediaFile(
                        path: path,
                        relativePath: relative,
                        sourceRoot: root.path,
                        size: size,
                        kind: kind,
                        modified: values.contentModificationDate
                    )
                )
                matchedBytes += size

                if scanned == 1 || scanned % 200 == 0 || files.count % 50 == 0 {
                    progress?(
                        MediaSearchProgress(
                            scanned: scanned,
                            matched: files.count,
                            bytes: matchedBytes,
                            currentPath: path,
                            elapsed: Date().timeIntervalSince(started)
                        )
                    )
                }

                if options.maxResults > 0, files.count >= options.maxResults {
                    truncated = true
                    break outer
                }
            }
        }

        files.sort {
            if $0.size == $1.size { return $0.path < $1.path }
            return $0.size > $1.size
        }

        let duration = Date().timeIntervalSince(started)
        progress?(
            MediaSearchProgress(
                scanned: scanned,
                matched: files.count,
                bytes: matchedBytes,
                currentPath: "",
                elapsed: duration
            )
        )

        return MediaSearchResult(
            files: files,
            skippedItems: skipped,
            duration: duration,
            truncated: truncated
        )
    }

    private static func prunedRoots(_ folders: [URL]) -> [URL] {
        var roots: [URL] = []
        for folder in folders {
            let standardized = folder.standardizedFileURL
            guard !roots.contains(where: { $0.path == standardized.path }) else { continue }
            roots.append(standardized)
        }
        roots.sort { $0.path.count < $1.path.count }

        var pruned: [URL] = []
        for root in roots {
            let isInsideAnother = pruned.contains { isDescendant(root.path, of: $0.path) }
            if !isInsideAnother { pruned.append(root) }
        }
        return pruned
    }

    private static func isDescendant(_ path: String, of root: String) -> Bool {
        if path == root { return true }
        if root == "/" { return path.hasPrefix("/") }
        return path.hasPrefix(root + "/")
    }

    private static func relativePath(of path: String, under root: String) -> String {
        if root == "/", path.hasPrefix("/") {
            return String(path.dropFirst())
        }
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return (path as NSString).lastPathComponent
    }
}
