import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    private var selectedCount: Int { model.selection.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)

            if selectedCount > 1 {
                multiSelection
            } else if let index = model.inspectorNode {
                InspectorDetails(index: index)
                    .environmentObject(model)
            } else {
                EmptyFolderView(
                    symbol: "sidebar.right",
                    title: "Ничего не выбрано",
                    message: "Выберите файл или папку, чтобы увидеть метаданные."
                )
            }
        }
        .frame(width: 280)
        .background(Theme.background)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.border).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Инспектор")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                model.showInspector = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Закрыть инспектор")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var multiSelection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Выбрано объектов: \(selectedCount)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(ByteFormat.string(model.selectedSize))
                        .font(AppFont.number(22))
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.currentRows.filter { model.selection.contains($0.id) }.prefix(8)) { row in
                        HStack(spacing: 6) {
                            NodeIcon(category: row.category, isContainer: row.isContainer, size: 18)
                            Text(row.name)
                                .font(.system(size: 10.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(ByteFormat.string(row.size))
                                .font(.system(size: 9.5))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 6) {
                    GhostButton(title: "Копировать пути", symbol: "doc.on.doc") {
                        model.copyPaths(Array(model.selection))
                    }
                    GhostButton(title: "В коллекцию", symbol: "tray.full") {
                        model.addToCollection(Array(model.selection))
                    }
                }

                AccentButton(title: "В Корзину…", symbol: "trash") {
                    model.requestTrashSelection()
                }
            }
            .padding(12)
        }
    }
}

private struct FileMetadata {
    let logicalSize: Int64?
    let created: Date?
    let modified: Date?
    let isPackage: Bool
}

private struct InspectorDetails: View {
    @EnvironmentObject private var model: AppModel
    let index: Int32
    @State private var metadata: FileMetadata?

    private var tree: ScanTree? { model.tree }
    private var node: ScanNode? {
        guard let tree, index >= 0, Int(index) < tree.count else { return nil }
        return tree.node(index)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                identity
                if node?.nodeKind == .aggregate {
                    aggregateNote
                } else {
                    sizes
                    dates
                    details
                    actions
                }
            }
            .padding(12)
        }
        .task(id: index) {
            await loadMetadata()
        }
    }

    @ViewBuilder
    private var identity: some View {
        if let tree, let node {
            HStack(alignment: .top, spacing: 10) {
                NodeIcon(category: tree.category(of: index), isContainer: node.nodeKind.isContainer, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(3)
                        .truncationMode(.middle)
                    Text(kindTitle(node.nodeKind))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(tree.path(of: index))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var sizes: some View {
        HStack(spacing: 8) {
            sizeCard("На диске", ByteFormat.string(node?.size ?? 0))
            sizeCard("Логический", metadata?.logicalSize.map(ByteFormat.string) ?? "—")
        }
    }

    private func sizeCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 9))
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 7) {
            infoRow("Изменён", dateText(metadata?.modified ?? tree?.modified(of: index)))
            infoRow("Создан", dateText(metadata?.created ?? tree?.created(of: index)))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let tree, let node {
                infoRow("Тип", tree.category(of: index).title)
                infoRow("Элементов", node.nodeKind.isContainer ? ByteFormat.count(Int(node.itemCount)) : "—")
                if node.nodeKind == .package, metadata?.isPackage == true {
                    infoRow("Пакет", "да, один объект")
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                GhostButton(title: "Finder", symbol: "magnifyingglass") {
                    model.reveal(indices: [index])
                }
                if node?.nodeKind == .file {
                    GhostButton(title: "Пробел", symbol: "eye") {
                        model.previewNode(index)
                    }
                }
            }
            HStack(spacing: 6) {
                GhostButton(title: "Копировать путь", symbol: "doc.on.doc") {
                    model.copyPaths([index])
                }
                GhostButton(title: "Терминал", symbol: "terminal") {
                    model.openInTerminal(index)
                }
            }
            GhostButton(
                title: model.isInCollection(index) ? "Убрать из коллекции" : "В коллекцию",
                symbol: "tray.full"
            ) {
                model.toggleCollection([index])
            }
            AccentButton(title: "В Корзину…", symbol: "trash") {
                model.selection = [index]
                model.requestTrashSelection()
            }
            .opacity(node?.nodeKind == .aggregate ? 0.4 : 1)
            .disabled(node?.nodeKind == .aggregate)
        }
    }

    private var aggregateNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Сводная строка")
                .font(.system(size: 11, weight: .semibold))
            Text(
                "Это файлы меньше 64 КБ, собранные в один объект. Сумма места точная, "
                    + "но по отдельности они не показываются и не удаляются из приложения."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 9))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var displayName: String {
        guard let tree, let node else { return "" }
        if node.nodeKind == .aggregate {
            return Plural.smallFiles(Int(node.itemCount))
        }
        let name = tree.name(of: index)
        return name.isEmpty ? "Без имени" : name
    }

    private func kindTitle(_ kind: NodeKind) -> String {
        switch kind {
        case .directory: return "Папка"
        case .file: return "Файл"
        case .package: return "Пакет"
        case .symlink: return "Символическая ссылка"
        case .aggregate: return "Мелкие файлы"
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func loadMetadata() async {
        guard let tree, index > 0, Int(index) < tree.count else {
            metadata = nil
            return
        }
        let node = tree.node(index)
        guard node.nodeKind != .aggregate else {
            metadata = nil
            return
        }
        let url = tree.url(of: index)
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isPackageKey,
        ])
        metadata = FileMetadata(
            logicalSize: values?.fileSize.map(Int64.init),
            created: values?.creationDate,
            modified: values?.contentModificationDate,
            isPackage: values?.isPackage ?? false
        )
    }
}
