import Foundation

/// Small, Codable summary shared by App Intents, Shortcuts and Finder actions.
public struct FolderScanSummary: Codable, Sendable {
    public let path: String
    public let name: String
    public let totalBytes: Int64
    public let totalHuman: String
    public let files: Int
    public let folders: Int
    public let hardLinkBytes: Int64
    public let durationSeconds: Double
    public let skippedItems: Int

    public init(
        path: String,
        name: String,
        totalBytes: Int64,
        files: Int,
        folders: Int,
        hardLinkBytes: Int64,
        durationSeconds: Double,
        skippedItems: Int
    ) {
        self.path = path
        self.name = name
        self.totalBytes = totalBytes
        self.totalHuman = ByteFormat.string(totalBytes)
        self.files = files
        self.folders = folders
        self.hardLinkBytes = hardLinkBytes
        self.durationSeconds = durationSeconds
        self.skippedItems = skippedItems
    }

    public static func scan(url: URL, options: ScanOptions = .balanced) throws -> FolderScanSummary {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ScanError.notDirectory(url.path)
        }
        let tree = try DiskScanner(options: options).scan(path: url.path)
        return FolderScanSummary(
            path: tree.rootPath,
            name: url.lastPathComponent.isEmpty ? tree.rootPath : url.lastPathComponent,
            totalBytes: tree.totalSize,
            files: tree.totalFiles,
            folders: tree.directoryCount(),
            hardLinkBytes: tree.report.hardLinkBytes,
            durationSeconds: tree.report.duration,
            skippedItems: tree.report.skippedItems
        )
    }
}
