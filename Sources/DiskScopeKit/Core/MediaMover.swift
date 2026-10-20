import Foundation

public struct MediaMoveFailure: Identifiable, Sendable {
    public let path: String
    public let name: String
    public let message: String

    public var id: String { path }

    public init(path: String, name: String, message: String) {
        self.path = path
        self.name = name
        self.message = message
    }
}

public struct MediaMoveResult: Sendable {
    public let moved: [MediaFile]
    public let failures: [MediaMoveFailure]
    public let destinationPath: String

    public init(moved: [MediaFile], failures: [MediaMoveFailure], destinationPath: String) {
        self.moved = moved
        self.failures = failures
        self.destinationPath = destinationPath
    }

    public var destination: URL { URL(fileURLWithPath: destinationPath) }

    public var movedBytes: Int64 {
        moved.reduce(Int64(0)) { $0 + $1.size }
    }
}

/// Moves media files into a destination folder. Existing names are preserved by
/// adding " 2", " 3", … before the extension. Cross-volume moves fall back to
/// copy + remove, and a failed copy never deletes the original.
public final class MediaMover {
    public init() {}

    public func move(
        files: [MediaFile],
        to destination: URL,
        progress: ((Int, Int) -> Void)? = nil
    ) -> MediaMoveResult {
        let fileManager = FileManager.default
        let destination = destination.standardizedFileURL

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                let failures = files.map {
                    MediaMoveFailure(
                        path: $0.path,
                        name: $0.name,
                        message: "«\(destination.lastPathComponent)» не является папкой."
                    )
                }
                return MediaMoveResult(
                    moved: [],
                    failures: failures,
                    destinationPath: destination.path
                )
            }
        } else {
            do {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                let failures = files.map {
                    MediaMoveFailure(
                        path: $0.path,
                        name: $0.name,
                        message: "Не удалось создать папку: \(error.localizedDescription)"
                    )
                }
                return MediaMoveResult(
                    moved: [],
                    failures: failures,
                    destinationPath: destination.path
                )
            }
        }

        var moved: [MediaFile] = []
        var failures: [MediaMoveFailure] = []

        for (offset, file) in files.enumerated() {
            let source = file.url.standardizedFileURL

            guard fileManager.fileExists(atPath: source.path) else {
                failures.append(
                    MediaMoveFailure(
                        path: file.path,
                        name: file.name,
                        message: "Файл не найден — возможно, он уже перемещён."
                    )
                )
                progress?(offset + 1, files.count)
                continue
            }

            if source.deletingLastPathComponent().standardizedFileURL.path == destination.path {
                failures.append(
                    MediaMoveFailure(
                        path: file.path,
                        name: file.name,
                        message: "Файл уже находится в выбранной папке."
                    )
                )
                progress?(offset + 1, files.count)
                continue
            }

            let target = uniqueDestination(for: source.lastPathComponent, in: destination)

            do {
                try moveFile(from: source, to: target, fileManager: fileManager)
                moved.append(file)
            } catch {
                failures.append(
                    MediaMoveFailure(
                        path: file.path,
                        name: file.name,
                        message: error.localizedDescription
                    )
                )
            }

            progress?(offset + 1, files.count)
        }

        return MediaMoveResult(
            moved: moved,
            failures: failures,
            destinationPath: destination.path
        )
    }

    private func moveFile(from source: URL, to target: URL, fileManager: FileManager) throws {
        do {
            try fileManager.moveItem(at: source, to: target)
            return
        } catch {
            // FileManager may refuse a move between volumes. Copy first and only
            // remove the source after the target is safely on disk.
            do {
                try fileManager.copyItem(at: source, to: target)
            } catch {
                try? fileManager.removeItem(at: target)
                throw error
            }

            do {
                try fileManager.removeItem(at: source)
            } catch {
                try? fileManager.removeItem(at: target)
                throw error
            }
        }
    }

    private func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let initial = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }

        let pathExtension = (fileName as NSString).pathExtension
        let base = pathExtension.isEmpty
            ? fileName
            : (fileName as NSString).deletingPathExtension

        for index in 2...10_000 {
            let candidateName = pathExtension.isEmpty
                ? "\(base) \(index)"
                : "\(base) \(index).\(pathExtension)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    }
}
