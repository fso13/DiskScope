import Foundation

extension AppModel {
    // MARK: - Scan history

    private var historyStore: ScanHistoryStore { ScanHistoryStore() }

    func recordScanHistory(_ tree: ScanTree) {
        var entries = historyStore.load()
        entries.insert(ScanHistoryEntry.make(tree: tree), at: 0)
        if entries.count > 30 {
            entries = Array(entries.prefix(30))
        }
        historyStore.save(entries)
        scanHistory = entries
    }

    public func reloadHistory() {
        scanHistory = historyStore.load()
    }

    public func deleteHistory(_ entry: ScanHistoryEntry) {
        let entries = historyStore.load().filter { $0.id != entry.id }
        historyStore.save(entries)
        scanHistory = entries
    }

    public func clearHistory() {
        historyStore.clear()
        scanHistory = []
    }

    public func historyDiff(for entry: ScanHistoryEntry) -> HistoryDiff {
        ScanHistoryDiff.make(entry: entry, tree: tree)
    }

    public func rescanHistory(_ entry: ScanHistoryEntry) {
        showHistory = false
        scan(path: entry.rootPath)
    }
}
