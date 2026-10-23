import Foundation

extension AppModel {
    public func rescanHistory(_ entry: ScanHistoryEntry) {
        history.show = false
        scan(path: entry.rootPath)
    }
}
