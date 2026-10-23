import AppKit
import Foundation

extension AppModel {
    // MARK: - Collection

    public var collectionCount: Int { collection.count }

    public var collectionSize: Int64 {
        guard let tree else { return 0 }
        return collection.reduce(Int64(0)) { total, index in
            Int(index) < tree.count ? total + tree.node(index).size : total
        }
    }

    public var collectionSummary: String {
        "\(Plural.items(collectionCount)) · \(ByteFormat.string(collectionSize))"
    }

    public var collectionTrashMessage: String {
        "\(collectionSummary). Файлы можно вернуть из Корзины через ⌘Z."
    }

    public var collectionRows: [ItemRow] {
        guard let tree else { return [] }
        return collection.compactMap { index -> ItemRow? in
            guard index > 0, Int(index) < tree.count, !tree.isDeleted(index) else { return nil }
            return ItemRowFactory.make(
                tree: tree,
                index: index,
                parentSize: max(tree.totalSize, 1),
                includePaths: true
            )
        }
        .sorted { $0.size > $1.size }
    }

    public func isInCollection(_ index: Int32) -> Bool {
        collection.contains(index)
    }

    public func addToCollection(_ indices: [Int32]) {
        guard let tree else { return }
        var updated = collection
        for index in indices {
            guard index > 0, Int(index) < tree.count, !tree.isDeleted(index) else { continue }
            guard tree.node(index).nodeKind != .aggregate else { continue }
            if updated.contains(where: { isAncestor($0, of: index, in: tree) }) { continue }
            updated = updated.filter { !isAncestor(index, of: $0, in: tree) }
            updated.insert(index)
        }
        collection = updated
    }

    public func removeFromCollection(_ indices: [Int32]) {
        collection.subtract(indices)
    }

    public func toggleCollection(_ indices: [Int32]) {
        guard !indices.isEmpty else { return }
        if indices.allSatisfy({ collection.contains($0) }) {
            removeFromCollection(indices)
        } else {
            addToCollection(indices)
        }
    }

    public func clearCollection() {
        collection = []
    }

    private func isAncestor(_ ancestor: Int32, of node: Int32, in tree: ScanTree) -> Bool {
        var cursor = tree.node(node).parent
        while cursor >= 0 {
            if cursor == ancestor { return true }
            cursor = tree.node(cursor).parent
        }
        return false
    }

    func resetCollection() {
        collection = []
        showCollection = false
        trash.showCollectionConfirmation = false
    }
}
