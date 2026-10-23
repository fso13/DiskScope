import Combine
import Foundation

/// Owns the volume overview: purgeable, Trash and snapshots.
@MainActor
public final class DiskModel: ObservableObject {
    @Published public internal(set) var overview: DiskOverview?
    @Published public internal(set) var loading = false
    @Published public internal(set) var error: String?

    private var volumeProvider: () -> VolumeInfo? = { nil }
    private var generation = 0

    public init() {}

    func attach(volumeProvider: @escaping () -> VolumeInfo?) {
        self.volumeProvider = volumeProvider
    }

    public func refresh(force: Bool = false) {
        guard !loading else { return }
        if !force, let overview, Date().timeIntervalSince(overview.updatedAt) < 60 {
            return
        }
        guard let volume = volumeProvider() else {
            error = "Не удалось определить внутренний диск"
            return
        }
        loading = true
        error = nil
        generation += 1
        let generation = generation
        let trashURL = DiskOverviewService.defaultTrashURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let overview = DiskOverviewService.load(volume: volume, trashURL: trashURL)
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.overview = overview
                self.loading = false
            }
        }
    }

    func preview(_ overview: DiskOverview) {
        generation += 1
        self.overview = overview
        loading = false
        error = nil
    }
}
