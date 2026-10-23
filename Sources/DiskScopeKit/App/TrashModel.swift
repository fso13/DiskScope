import Combine
import Foundation

/// Owns trash confirmations, the busy flag and the undo stack.
@MainActor
public final class TrashModel: ObservableObject {
    @Published public var showSelectionConfirmation = false
    @Published public var showCollectionConfirmation = false
    @Published public internal(set) var canUndo = false
    @Published public internal(set) var busy = false

    private var stack: [TrashUndoEntry] = []

    public init() {}

    func record(
        removal: ScanTreeRemoval,
        trashed: [(index: Int32, original: URL, trashed: URL)],
        collectionRoots: [Int32]
    ) {
        var files: [TrashUndoFile] = []
        for item in trashed {
            guard let group = removal.groups.first(where: { $0.root == item.index }) else { continue }
            files.append(TrashUndoFile(
                originalURL: item.original,
                trashedURL: item.trashed,
                group: group
            ))
        }
        guard !files.isEmpty else { return }
        let roots = Array(Set(files.map { $0.group.root }))
        stack.append(TrashUndoEntry(
            files: files,
            collectionRoots: collectionRoots.filter { roots.contains($0) }
        ))
        if stack.count > 10 { stack.removeFirst() }
        canUndo = true
    }

    func popUndo() -> TrashUndoEntry? {
        let entry = stack.popLast()
        canUndo = !stack.isEmpty
        return entry
    }

    func reset() {
        stack.removeAll()
        canUndo = false
    }
}

struct TrashUndoFile: Sendable {
    let originalURL: URL
    let trashedURL: URL
    let group: ScanTreeRemoval.Group
}

struct TrashUndoEntry: Sendable {
    let files: [TrashUndoFile]
    let collectionRoots: [Int32]
}
