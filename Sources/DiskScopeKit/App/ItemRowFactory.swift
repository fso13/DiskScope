import Foundation

enum ItemRowFactory {
    static func make(
        tree: ScanTree,
        index: Int32,
        parentSize: Int64,
        includePaths: Bool
    ) -> AppModel.ItemRow {
        let node = tree.node(index)
        let isAggregate = node.nodeKind == .aggregate
        let name: String
        if isAggregate {
            name = "Мелкие файлы"
        } else {
            name = TreeNaming.name(tree: tree, index: index)
        }
        return AppModel.ItemRow(
            id: index,
            name: name,
            path: includePaths ? tree.path(of: index) : "",
            relativePath: includePaths ? tree.relativePath(of: index) : "",
            size: node.size,
            category: tree.category(of: index),
            isContainer: node.nodeKind.isContainer,
            isAggregate: isAggregate,
            isHardLink: node.isHardLink,
            itemCount: Int(node.itemCount),
            fraction: parentSize > 0 ? Double(node.size) / Double(parentSize) : 0,
            depth: 0
        )
    }
}
