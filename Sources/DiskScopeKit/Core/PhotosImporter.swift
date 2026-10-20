import Foundation
import Photos

public struct PhotosImportFailure: Identifiable, Sendable {
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

public struct PhotosImportResult: Sendable {
    public let imported: [MediaFile]
    public let skipped: [MediaFile]
    public let failures: [PhotosImportFailure]

    public init(imported: [MediaFile], skipped: [MediaFile], failures: [PhotosImportFailure]) {
        self.imported = imported
        self.skipped = skipped
        self.failures = failures
    }

    public var importedBytes: Int64 {
        imported.reduce(Int64(0)) { $0 + $1.size }
    }
}

public enum PhotosImportError: Error, LocalizedError {
    case accessDenied
    case cancelled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Нет доступа к «Фото». Разрешите DiskScope доступ в «Настройки → Конфиденциальность и безопасность → Фото»."
        case .cancelled:
            return "Импорт в «Фото» отменён"
        case .failed(let message):
            return message
        }
    }
}

/// Imports images into the system Photos library. `shouldMoveFile` makes Photos
/// take ownership of the original; if the file is still present after a
/// successful import it is moved to the Trash so the operation really is a move.
public final class PhotosImporter {
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jfif", "png", "gif", "heic", "heif", "tif", "tiff",
        "bmp", "webp", "avif", "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2",
    ]

    public init() {}

    public static func supports(_ file: MediaFile) -> Bool {
        file.kind == .image && supportedExtensions.contains(file.fileExtension)
    }

    public func importImages(
        _ files: [MediaFile],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> PhotosImportResult {
        let status = await Self.requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw PhotosImportError.accessDenied
        }

        let candidates = files.filter(Self.supports)
        let skipped = files.filter { !Self.supports($0) }
        guard !candidates.isEmpty else {
            return PhotosImportResult(imported: [], skipped: skipped, failures: [])
        }

        let fileManager = FileManager.default
        var imported: [MediaFile] = []
        var failures: [PhotosImportFailure] = []

        for (offset, file) in candidates.enumerated() {
            if Task.isCancelled { throw PhotosImportError.cancelled }

            guard fileManager.fileExists(atPath: file.path) else {
                failures.append(
                    PhotosImportFailure(
                        path: file.path,
                        name: file.name,
                        message: "Файл не найден — возможно, он уже перемещён."
                    )
                )
                progress?(offset + 1, candidates.count)
                continue
            }

            do {
                try await importOne(file)

                // Normally Photos moved the file itself. If it copied instead,
                // finish the move by putting the original in the Trash.
                if fileManager.fileExists(atPath: file.path) {
                    do {
                        try fileManager.trashItem(at: file.url, resultingItemURL: nil)
                    } catch {
                        failures.append(
                            PhotosImportFailure(
                                path: file.path,
                                name: file.name,
                                message: "Импортировано в «Фото», но оригинал не удалось переместить в Корзину: \(error.localizedDescription)"
                            )
                        )
                        progress?(offset + 1, candidates.count)
                        continue
                    }
                }

                imported.append(file)
            } catch {
                failures.append(
                    PhotosImportFailure(
                        path: file.path,
                        name: file.name,
                        message: error.localizedDescription
                    )
                )
            }

            progress?(offset + 1, candidates.count)
        }

        return PhotosImportResult(imported: imported, skipped: skipped, failures: failures)
    }

    private func importOne(_ file: MediaFile) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                request.addResource(with: .photo, fileURL: file.url, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? PhotosImportError.failed("Photos не принял «\(file.name)».")
                    )
                }
            }
        }
    }

    private static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
