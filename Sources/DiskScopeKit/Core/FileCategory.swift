import Foundation

/// Broad file families used for colour coding and the "Types" breakdown.
public enum FileCategory: Int, CaseIterable, Identifiable, Sendable {
    case video
    case image
    case audio
    case archive
    case document
    case app
    case code
    case other

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .video: return "Видео"
        case .image: return "Изображения"
        case .audio: return "Аудио"
        case .archive: return "Архивы и образы"
        case .document: return "Документы"
        case .app: return "Приложения"
        case .code: return "Код и данные"
        case .other: return "Другое"
        }
    }

    public var symbolName: String {
        switch self {
        case .video: return "film.fill"
        case .image: return "photo.fill"
        case .audio: return "music.note"
        case .archive: return "archivebox.fill"
        case .document: return "doc.text.fill"
        case .app: return "app.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "square.grid.2x2.fill"
        }
    }

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "mkv", "avi", "m4v", "mpg", "mpeg", "webm", "flv", "wmv",
        "ts", "mts", "m2ts", "vob", "3gp", "ogv", "rmvb", "asf", "divx", "mxf",
    ]
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "raw",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "psd", "ai", "sketch",
        "webp", "icns", "svg", "exr", "hdr",
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "wma",
        "alac", "ape", "m4b", "caf", "dsf", "dff",
    ]
    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "dmg", "iso",
        "pkg", "xip", "cab", "lzma", "lz4", "sit", "sitx", "img", "sparseimage",
        "sparsebundle",
    ]
    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers",
        "key", "txt", "rtf", "rtfd", "csv", "tsv", "epub", "mobi", "odt", "ods",
        "md", "html", "htm", "xml", "json", "yaml", "yml", "log", "plist",
    ]
    private static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx", "java", "kt",
        "kts", "js", "jsx", "ts", "tsx", "py", "rb", "php", "go", "rs", "cs",
        "scala", "sh", "bash", "zsh", "fish", "sql", "ipynb", "css", "scss",
        "less", "vue", "svelte", "dart", "lua", "r", "pl", "asm", "s", "gradle",
        "toml", "ini", "cfg", "conf", "xcconfig", "pbxproj", "metal", "glsl",
        "frag", "vert", "strings", "stringsdict", "xib", "storyboard", "ttf",
        "otf", "woff", "woff2", "eot",
    ]

    public static func forExtension(_ ext: String) -> FileCategory {
        let ext = ext.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if imageExtensions.contains(ext) { return .image }
        if audioExtensions.contains(ext) { return .audio }
        if archiveExtensions.contains(ext) { return .archive }
        if documentExtensions.contains(ext) { return .document }
        if codeExtensions.contains(ext) { return .code }
        return .other
    }

    /// Categories used by a directory package, based on its bundle extension.
    public static func forPackageExtension(_ ext: String) -> FileCategory {
        .app
    }
}
