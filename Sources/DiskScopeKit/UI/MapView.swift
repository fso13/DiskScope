import AppKit
import SwiftUI

struct ChildrenTable: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Table(model.currentRows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Имя", value: \.name) { row in
                nameCell(row)
            }
            .width(min: 200, ideal: 330, max: 720)

            TableColumn("Размер", value: \.size) { row in
                Text(ByteFormat.string(row.size))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 96, max: 120)

            TableColumn("Доля", value: \.fraction) { row in
                VStack(alignment: .trailing, spacing: 3) {
                    Text(row.fraction.formatted(.percent.precision(.fractionLength(row.fraction < 0.1 ? 2 : 0))))
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    ProgressBar(
                        fraction: row.fraction,
                        tint: AnyShapeStyle(Theme.categoryColor(row.category).opacity(0.85)),
                        height: 2.5
                    )
                    .frame(width: 46)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 2)
            }
            .width(min: 62, ideal: 72, max: 90)

            TableColumn("Элементы", value: \.itemCount) { row in
                Text(row.isContainer ? ByteFormat.count(row.itemCount) : "—")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 74, max: 96)

            TableColumn("Тип") { row in
                HStack(spacing: 5) {
                    CategoryDot(category: row.category, size: 6)
                    Text(LocalizedStringKey(typeLabel(row)))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(
                min: model.showInspector ? 0 : 82,
                ideal: model.showInspector ? 0 : 104,
                max: model.showInspector ? 0 : 130
            )
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .onKeyPress(.space) {
            model.previewSelection()
            return .handled
        }
        .contextMenu(forSelectionType: Int32.self) { selection in
            if let first = selection.first {
                let isAggregate = model.tree?.node(first).nodeKind == .aggregate
                let isContainer = model.tree?.node(first).nodeKind.isContainer == true
                Button("Открыть") { model.openRow(first) }
                    .disabled(isAggregate)
                Button("Показать в Finder") { model.reveal(indices: Array(selection)) }
                if !isContainer {
                    Button("Быстрый просмотр") { model.previewNode(first) }
                }
                if isContainer {
                    Button("Сканировать эту папку") {
                        if let path = model.tree?.path(of: first) { model.scan(path: path) }
                    }
                }
                Button("Копировать путь") { model.copyPaths(Array(selection)) }
                Button("Открыть в терминале") { model.openInTerminal(first) }
                let allCollected = selection.allSatisfy { model.isInCollection($0) }
                Button(allCollected ? "Убрать из коллекции" : "В коллекцию") {
                    if allCollected {
                        model.removeFromCollection(Array(selection))
                    } else {
                        model.addToCollection(Array(selection))
                    }
                }
                Divider()
                Button("Переместить в Корзину…", role: .destructive) {
                    model.selection = selection
                    model.requestTrashSelection()
                }
                .disabled(isAggregate)
            }
        } primaryAction: { selection in
            if let first = selection.first {
                model.activateRow(first)
            }
        }
    }

    private func nameCell(_ row: AppModel.ItemRow) -> some View {
        HStack(spacing: 8) {
            NodeIcon(category: row.category, isContainer: row.isContainer, size: 21)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 11.5, weight: row.isContainer ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if row.isHardLink {
                        Image(systemName: "link")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .help("Жёсткая ссылка: размер уже учтён в другой записи")
                    }
                }
                if row.isAggregate {
                    Text("меньше 64 КБ · \(Plural.files(row.itemCount))")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func typeLabel(_ row: AppModel.ItemRow) -> String {
        if row.isAggregate { return "Мелкие файлы" }
        if row.isContainer {
            return row.category == .app ? "Приложение" : "Папка"
        }
        return row.category.title
    }
}

struct MapView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            treemapCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            childrenCard
                .frame(height: 300)
        }
    }

    private var treemapCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Карта папки")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("· \(Plural.elements(model.currentDirectCount))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Нажмите на папку, чтобы открыть · двойной клик в таблице")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Rectangle().fill(Theme.border).frame(height: 1)

            if let tree = model.tree {
                TreemapView(tree: tree, root: model.currentIndex)
                    .padding(6)
            } else {
                EmptyFolderView(symbol: "chart.pie", title: "Нет данных", message: "Сначала просканируйте папку.")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var childrenCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Содержимое")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("· \(Plural.items(model.currentRowsTotal))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.currentRowsTruncated {
                    Text("показаны крупнейшие \(ByteFormat.count(model.currentRows.count))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Rectangle().fill(Theme.border).frame(height: 1)

            if model.currentRows.isEmpty {
                if model.searchText.isEmpty {
                    EmptyFolderView(
                        symbol: "folder",
                        title: "Папка пуста",
                        message: "Здесь нет файлов, которые можно показать."
                    )
                } else {
                    EmptyFolderView(
                        symbol: "magnifyingglass",
                        title: "Ничего не найдено",
                        message: "Попробуйте изменить фильтр."
                    )
                }
            } else {
                ChildrenTable()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }
}
