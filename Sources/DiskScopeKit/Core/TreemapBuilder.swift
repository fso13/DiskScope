import CoreGraphics
import Foundation

/// One rectangle of the treemap, linked to a node of the scan tree.
/// `node == nil` represents the "rest" bucket for very large folders.
public struct TreemapCell: Identifiable, Sendable {
    public let id: Int
    public let node: Int32?
    /// Identifier of the enclosing depth-1 cell for nested cells.
    public let parentID: Int?
    public let depth: Int
    public let rect: CGRect
    public let size: Int64
    /// Share of the parent container.
    public let fraction: Double
    public let name: String
    public let category: FileCategory
    public let isContainer: Bool
    /// Number of items folded into a "rest" cell.
    public let restCount: Int

    public var clickable: Bool { node != nil }
}

public enum TreemapBuilder {
    /// Builds a two level treemap for `root`.
    /// - Parameters:
    ///   - maxChildren: how many direct children are drawn individually.
    ///   - maxSubChildren: how many children each big folder subdivides into.
    public static func build(
        tree: ScanTree,
        root: Int32,
        size: CGSize,
        maxChildren: Int = 320,
        maxSubChildren: Int = 32,
        maxSubCells: Int = 700,
        padding: CGFloat = 4
    ) -> [TreemapCell] {
        guard size.width > 1, size.height > 1 else { return [] }
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: padding, dy: padding)
        guard outer.width > 1, outer.height > 1 else { return [] }

        let rootSize = max(tree.node(root).size, 1)
        var allChildren = tree.children(of: root)
            .filter { tree.node($0).size > 0 }
            .sorted { tree.node($0).size > tree.node($1).size }
        guard !allChildren.isEmpty else { return [] }

        var restSize: Int64 = 0
        var restCount = 0
        if allChildren.count > maxChildren {
            let tail = allChildren[maxChildren...]
            restSize = tail.reduce(Int64(0)) { $0 + tree.node($1).size }
            restCount = tail.count
            allChildren = Array(allChildren.prefix(maxChildren))
        }

        var values = allChildren.map { Double(tree.node($0).size) }
        if restSize > 0 { values.append(Double(restSize)) }
        let rects = TreemapLayout.layout(values: values, in: outer)

        var cells: [TreemapCell] = []
        cells.reserveCapacity(values.count + 128)
        var identifier = 0
        var subBudget = maxSubCells

        var primary: [(node: Int32, rect: CGRect, size: Int64, id: Int)] = []
        for (index, nodeIndex) in allChildren.enumerated() {
            let node = tree.node(nodeIndex)
            let rect = rects[index].insetBy(dx: 1.1, dy: 1.1)
            guard rect.width > 1, rect.height > 1 else { continue }
            let cellID = identifier
            identifier += 1
            primary.append((nodeIndex, rect, node.size, cellID))
            cells.append(TreemapCell(
                id: cellID,
                node: nodeIndex,
                parentID: nil,
                depth: 1,
                rect: rect,
                size: node.size,
                fraction: rootSize > 0 ? Double(node.size) / Double(rootSize) : 0,
                name: displayName(tree: tree, node: nodeIndex),
                category: categoryFor(tree: tree, node: nodeIndex),
                isContainer: node.nodeKind.isContainer,
                restCount: 0
            ))
        }

        if restSize > 0, rects.count > allChildren.count {
            let rect = rects[allChildren.count].insetBy(dx: 1.1, dy: 1.1)
            if rect.width > 1, rect.height > 1 {
                cells.append(TreemapCell(
                    id: identifier,
                    node: nil,
                    parentID: nil,
                    depth: 1,
                    rect: rect,
                    size: restSize,
                    fraction: rootSize > 0 ? Double(restSize) / Double(rootSize) : 0,
                    name: "Ещё \(Plural.items(restCount))",
                    category: .other,
                    isContainer: false,
                    restCount: restCount
                ))
                identifier += 1
            }
        }

        for entry in primary {
            guard subBudget > 0 else { break }
            let node = tree.node(entry.node)
            guard node.nodeKind == .directory, node.size > 0 else { continue }
            let area = entry.rect.width * entry.rect.height
            guard area > 3_800, entry.rect.width > 56, entry.rect.height > 62 else { continue }

            var children = tree.children(of: entry.node)
                .filter { tree.node($0).size > 0 }
                .sorted { tree.node($0).size > tree.node($1).size }
            guard !children.isEmpty else { continue }

            var subRestSize: Int64 = 0
            var subRestCount = 0
            let limit = min(maxSubChildren, subBudget)
            if children.count > limit {
                let tail = children[limit...]
                subRestSize = tail.reduce(Int64(0)) { $0 + tree.node($1).size }
                subRestCount = tail.count
                children = Array(children.prefix(limit))
            }

            var subValues = children.map { Double(tree.node($0).size) }
            if subRestSize > 0 { subValues.append(Double(subRestSize)) }
            guard !subValues.isEmpty else { continue }

            let labelStrip: CGFloat = 18
            let inner = CGRect(
                x: entry.rect.minX + 2.4,
                y: entry.rect.minY + 2.4 + labelStrip,
                width: entry.rect.width - 4.8,
                height: entry.rect.height - 4.8 - labelStrip
            )
            guard inner.width > 20, inner.height > 18 else { continue }
            let subRects = TreemapLayout.layout(values: subValues, in: inner)
            let parentSize = max(node.size, 1)

            for (index, childIndex) in children.enumerated() {
                guard index < subRects.count else { break }
                let rect = subRects[index].insetBy(dx: 0.7, dy: 0.7)
                guard rect.width > 1.2, rect.height > 1.2 else { continue }
                let child = tree.node(childIndex)
                cells.append(TreemapCell(
                    id: identifier,
                    node: childIndex,
                    parentID: entry.id,
                    depth: 2,
                    rect: rect,
                    size: child.size,
                    fraction: Double(child.size) / Double(parentSize),
                    name: displayName(tree: tree, node: childIndex),
                    category: categoryFor(tree: tree, node: childIndex),
                    isContainer: child.nodeKind.isContainer,
                    restCount: 0
                ))
                identifier += 1
            }

            if subRestSize > 0, subRects.count > children.count {
                let rect = subRects[children.count].insetBy(dx: 0.7, dy: 0.7)
                if rect.width > 1.2, rect.height > 1.2 {
                    cells.append(TreemapCell(
                        id: identifier,
                        node: nil,
                        parentID: entry.id,
                        depth: 2,
                        rect: rect,
                        size: subRestSize,
                        fraction: Double(subRestSize) / Double(parentSize),
                        name: "Ещё \(Plural.items(subRestCount))",
                        category: .other,
                        isContainer: false,
                        restCount: subRestCount
                    ))
                    identifier += 1
                }
            }
            subBudget -= children.count + (subRestSize > 0 ? 1 : 0)
        }

        return cells
    }

    public static func displayName(tree: ScanTree, node: Int32) -> String {
        if tree.node(node).nodeKind == .aggregate {
            let count = Int(tree.node(node).itemCount)
            return Plural.smallFiles(count)
        }
        let name = tree.name(of: node)
        return name.isEmpty ? "Без имени" : name
    }

    /// Packages use the category of what they contain, while the table still
    /// labels them as applications.
    private static func categoryFor(tree: ScanTree, node: Int32) -> FileCategory {
        let value = tree.node(node)
        if value.nodeKind == .file {
            return tree.category(of: node)
        }
        if value.nodeKind == .aggregate {
            return .other
        }
        return value.category
    }
}
