import AppKit
import SwiftUI

struct TreemapView: View {
    @EnvironmentObject private var model: AppModel
    let tree: ScanTree
    let root: Int32

    @State private var hoveredID: Int?
    @State private var hoverPoint: CGPoint = .zero
    @State private var previewNode: Int32?
    @State private var cache = TreemapCache()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cells = cache.cells(tree: tree, root: root, size: size)

            ZStack(alignment: .topLeading) {
                if cells.isEmpty {
                    EmptyFolderView(
                        symbol: "rectangle.dashed",
                        title: "Здесь пусто",
                        message: "В этой папке нет файлов, либо всё содержимое уже удалено."
                    )
                } else {
                    Canvas { context, _ in
                        let subdivided = Set(cells.compactMap(\.parentID))
                        for cell in cells where cell.depth == 1 {
                            draw(
                                cell: cell,
                                in: &context,
                                hovered: cell.id == hoveredID,
                                compactLabel: subdivided.contains(cell.id)
                            )
                        }
                        for cell in cells where cell.depth == 2 {
                            draw(cell: cell, in: &context, hovered: cell.id == hoveredID, compactLabel: false)
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            hoverPoint = point
                            hoveredID = hitTest(cells, at: point)?.id
                        case .ended:
                            hoveredID = nil
                        }
                    }
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleClick(at: value.location, cells: cells)
                            }
                    )

                    if let hoveredID, let cell = cells.first(where: { $0.id == hoveredID }) {
                        tooltip(for: cell, in: size)
                            .allowsHitTesting(false)
                    }
                }

                if let previewNode, isValid(node: previewNode) {
                    previewCard(node: previewNode, in: size)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .clipped()
        .onChange(of: root) { _, _ in
            hoveredID = nil
            previewNode = nil
        }
        .onChange(of: tree.totalSize) { _, _ in
            if let previewNode, !isValid(node: previewNode) { self.previewNode = nil }
        }
    }

    // MARK: - Interaction

    private func hitTest(_ cells: [TreemapCell], at point: CGPoint) -> TreemapCell? {
        var best: TreemapCell?
        for cell in cells where cell.rect.contains(point) {
            if let current = best {
                if cell.depth > current.depth ||
                    (cell.depth == current.depth && cell.rect.width * cell.rect.height < current.rect.width * current.rect.height) {
                    best = cell
                }
            } else {
                best = cell
            }
        }
        return best
    }

    private func handleClick(at point: CGPoint, cells: [TreemapCell]) {
        guard let cell = hitTest(cells, at: point), let node = cell.node else {
            previewNode = nil
            return
        }
        let kind = tree.node(node).nodeKind
        if kind.isContainer {
            previewNode = nil
            withAnimation(.easeOut(duration: 0.16)) {
                model.navigate(to: node)
            }
        } else if kind == .aggregate {
            return
        } else {
            model.selection = [node]
            withAnimation(.easeOut(duration: 0.15)) {
                previewNode = node
            }
        }
    }

    private func isValid(node: Int32) -> Bool {
        node >= 0 && Int(node) < tree.count && !tree.isDeleted(node) && !tree.node(node).nodeKind.isContainer
    }

    // MARK: - Drawing

    private func draw(cell: TreemapCell, in context: inout GraphicsContext, hovered: Bool, compactLabel: Bool) {
        let rect = cell.rect
        guard rect.width > 1, rect.height > 1 else { return }
        let radius: CGFloat = cell.depth == 1 ? 6 : 4
        let path = Path(roundedRect: rect, cornerRadius: radius)

        let base = Theme.treemapColor(category: cell.category, seed: cell.id, isContainer: cell.isContainer)
        let variation = Double((cell.id * 37) % 7) * 0.008
        let topOpacity = (cell.depth == 1 ? 1.0 : 0.92) - variation
        let bottomOpacity = (cell.depth == 1 ? 0.86 : 0.72) - variation

        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [base.opacity(topOpacity), base.opacity(bottomOpacity)]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )

        context.stroke(
            path,
            with: .color(Color.white.opacity(cell.depth == 1 ? 0.13 : 0.10)),
            lineWidth: 0.8
        )

        if hovered {
            context.fill(path, with: .color(Color.white.opacity(0.14)))
            context.stroke(path, with: .color(Color.white.opacity(0.85)), lineWidth: 1.6)
        }

        drawLabels(cell: cell, in: &context, compact: compactLabel)
    }

    private func drawLabels(cell: TreemapCell, in context: inout GraphicsContext, compact: Bool) {
        let rect = cell.rect
        let isTop = cell.depth == 1
        let nameSize: CGFloat = isTop ? 11 : 9.5
        let sizeSize: CGFloat = compact ? 9.5 : (isTop ? 9.5 : 8.5)
        let minWidth: CGFloat = isTop ? 66 : 58
        let minHeight: CGFloat = isTop ? 24 : 18
        guard rect.width >= minWidth, rect.height >= minHeight else { return }

        let inset: CGFloat = isTop ? 7 : 4
        let availableWidth = rect.width - inset * 2
        guard availableWidth > 16 else { return }

        let darkText = Theme.treemapUsesDarkText(category: cell.category, isContainer: cell.isContainer)
        let shadowColor = darkText ? Color.white.opacity(0.28) : Color.black.opacity(0.30)
        let nameColor = Theme.treemapTextColor(category: cell.category, isContainer: cell.isContainer)
        let sizeColor = Theme.treemapSecondaryTextColor(category: cell.category, isContainer: cell.isContainer)

        let sizeString = ByteFormat.string(cell.size)
        var nameWidth = availableWidth
        if compact {
            nameWidth = max(20, availableWidth - CGFloat(sizeString.count) * sizeSize * 0.58 - 12)
        }

        let name = truncated(cell.name, width: nameWidth, fontSize: nameSize)
        let nameText = Text(name)
            .font(.system(size: nameSize, weight: .semibold))
            .foregroundColor(nameColor)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: shadowColor, radius: 1.2, x: 0, y: 1))
            layer.draw(nameText, at: CGPoint(x: rect.minX + inset, y: rect.minY + inset - 1), anchor: .topLeading)
        }

        if compact {
            let sizeText = Text(sizeString)
                .font(.system(size: sizeSize, weight: .medium))
                .foregroundColor(sizeColor)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: shadowColor.opacity(0.7), radius: 1.2, x: 0, y: 1))
                layer.draw(sizeText, at: CGPoint(x: rect.maxX - inset, y: rect.minY + inset - 1), anchor: .topTrailing)
            }
            return
        }

        let canShowSize = isTop ? rect.height >= 42 : rect.height >= 34
        if canShowSize {
            let sizeText = Text(sizeString)
                .font(.system(size: sizeSize, weight: .medium))
                .foregroundColor(sizeColor)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: shadowColor.opacity(0.7), radius: 1.2, x: 0, y: 1))
                layer.draw(sizeText, at: CGPoint(x: rect.minX + inset, y: rect.minY + inset + nameSize + 3), anchor: .topLeading)
            }
        }
    }

    private func truncated(_ text: String, width: CGFloat, fontSize: CGFloat) -> String {
        guard !text.isEmpty else { return text }
        let approximateCharacterWidth = fontSize * 0.55
        let maxCharacters = max(1, Int(width / approximateCharacterWidth))
        if text.count <= maxCharacters { return text }
        guard maxCharacters > 2 else { return String(text.prefix(1)) }
        return String(text.prefix(maxCharacters - 1)) + "…"
    }

    // MARK: - Overlays

    private func tooltip(for cell: TreemapCell, in size: CGSize) -> some View {
        let width: CGFloat = 258
        let x = min(max(hoverPoint.x + 16, 8), max(8, size.width - width - 10))
        let y = min(max(hoverPoint.y + 16, 8), max(8, size.height - 96))

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                CategoryDot(category: cell.category)
                Text(cell.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(ByteFormat.string(cell.size))
                    .font(AppFont.number(12.5))
                    .monospacedDigit()
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(cell.fraction.formatted(.percent.precision(.fractionLength(1))))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(hint(for: cell))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(width: width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .offset(x: x, y: y)
    }

    private func hint(for cell: TreemapCell) -> String {
        guard let node = cell.node else {
            return "Ещё \(Plural.items(cell.restCount)) — откройте таблицу ниже"
        }
        let kind = tree.node(node).nodeKind
        if kind.isContainer {
            return "Нажмите, чтобы открыть папку"
        }
        return "Нажмите, чтобы посмотреть файл"
    }

    private func previewCard(node: Int32, in size: CGSize) -> some View {
        let category = tree.category(of: node)
        let name = TreeNaming.name(tree: tree, index: node)
        let nodeSize = tree.node(node).size
        return HStack(spacing: 10) {
            NodeIcon(category: category, isContainer: false, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(ByteFormat.string(nodeSize)) · \(tree.relativePath(of: node))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            GhostButton(title: "Finder", symbol: "magnifyingglass") {
                model.reveal(indices: [node])
            }
            GhostButton(title: "В Корзину", symbol: "trash", tint: Theme.danger) {
                model.selection = [node]
                model.requestTrashSelection()
            }
            Button {
                previewNode = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Theme.subtleFill, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: min(540, size.width - 24))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 12, y: 5)
    }
}

/// Caches the treemap layout between hover updates and window resizes.
private final class TreemapCache {
    private struct Key: Equatable {
        let tree: ObjectIdentifier
        let root: Int32
        let width: Int
        let height: Int
        let total: Int64
    }

    private var key: Key?
    private var cached: [TreemapCell] = []

    func cells(tree: ScanTree, root: Int32, size: CGSize) -> [TreemapCell] {
        let newKey = Key(
            tree: ObjectIdentifier(tree),
            root: root,
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded()),
            total: tree.totalSize
        )
        if newKey != key {
            key = newKey
            cached = TreemapBuilder.build(tree: tree, root: root, size: size)
        }
        return cached
    }
}
