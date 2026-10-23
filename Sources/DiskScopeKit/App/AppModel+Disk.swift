import AppKit
import Foundation

extension AppModel {
    // MARK: - Disk overview

    public func refreshDiskOverview(force: Bool = false) {
        disk.refresh(force: force)
    }

    public func showDiskOverview() {
        tab = .disk
        disk.refresh(force: true)
    }

    public func openTrash() {
        let url = disk.overview?.trash.url ?? DiskOverviewService.defaultTrashURL
        NSWorkspace.shared.open(url)
    }
}
