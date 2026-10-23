import Combine
import Foundation

/// Owns the persisted scan history and its diff against the current tree.
@MainActor
public final class HistoryModel: ObservableObject {
    @Published public internal(set) var entries: [ScanHistoryEntry] = []
    @Published public var show = false

    private let store: ScanHistoryStore
    private var treeProvider: () -> ScanTree? = { nil }

    public init(store: ScanHistoryStore = ScanHistoryStore()) {
        self.store = store
        entries = store.load()
    }

    func attach(treeProvider: @escaping () -> ScanTree?) {
        self.treeProvider = treeProvider
    }

    func record(_ tree: ScanTree) {
        var updated = store.load()
        updated.insert(ScanHistoryEntry.make(tree: tree), at: 0)
        if updated.count > 30 { updated = Array(updated.prefix(30)) }
        store.save(updated)
        entries = updated
    }

    public func reload() {
        entries = store.load()
    }

    public func delete(_ entry: ScanHistoryEntry) {
        let updated = store.load().filter { $0.id != entry.id }
        store.save(updated)
        entries = updated
    }

    public func clear() {
        store.clear()
        entries = []
    }

    public func diff(for entry: ScanHistoryEntry) -> HistoryDiff {
        ScanHistoryDiff.make(entry: entry, tree: treeProvider())
    }
}
