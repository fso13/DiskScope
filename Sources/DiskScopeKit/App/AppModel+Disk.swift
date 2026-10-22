import AppKit
import Foundation

extension AppModel {
    // MARK: - Disk overview

    public func refreshDiskOverview(force: Bool = false) {
        guard !diskOverviewLoading else { return }
        if !force, let diskOverview, Date().timeIntervalSince(diskOverview.updatedAt) < 60 {
            return
        }
        guard let volume = internalVolume else {
            diskOverviewError = "Не удалось определить внутренний диск"
            return
        }
        diskOverviewLoading = true
        diskOverviewError = nil
        let trashURL = DiskOverviewService.defaultTrashURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let overview = DiskOverviewService.load(volume: volume, trashURL: trashURL)
            DispatchQueue.main.async {
                guard let self else { return }
                self.diskOverview = overview
                self.diskOverviewLoading = false
            }
        }
    }

    public func showDiskOverview() {
        tab = .disk
        refreshDiskOverview(force: true)
    }

    public func openTrash() {
        let url = diskOverview?.trash.url ?? DiskOverviewService.defaultTrashURL
        NSWorkspace.shared.open(url)
    }
}
