import Combine
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable, Identifiable {
        let version: String
        let pageURL: URL
        let downloadURL: URL?

        var id: String { version }
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var task: Task<Void, Never>?

    func check(currentVersion: String) {
        guard state != .checking else { return }
        task?.cancel()
        state = .checking

        task = Task { [weak self] in
            do {
                let release = try await Self.fetchLatest(currentVersion: currentVersion)
                guard !Task.isCancelled else { return }
                if Self.isNewer(release.version, than: currentVersion) {
                    self?.state = .available(release)
                } else {
                    self?.state = .upToDate(currentVersion)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed("Не удалось проверить обновления. Проверьте подключение и повторите.")
            }
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ raw: String) -> [Int] {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        return value.split(separator: ".").map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }

    private static func fetchLatest(currentVersion: String) async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/fso13/DiskScope/releases/latest") else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DiskScope/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.http(http.statusCode)
        }

        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let pageURL = URL(string: payload.htmlURL) else {
            throw UpdateError.invalidURL
        }

        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName
        let asset = payload.assets.first { $0.name == "DiskScope-macos-universal.dmg" }
            ?? payload.assets.first { $0.name.hasSuffix(".dmg") }
        let downloadURL = asset.flatMap { URL(string: $0.browserDownloadURL) }

        return Release(version: version, pageURL: pageURL, downloadURL: downloadURL)
    }
}

private enum UpdateError: Error {
    case invalidURL
    case invalidResponse
    case http(Int)
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
