import AppKit
import SwiftUI

struct LargestFilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sortOrder: [KeyPathComparator<AppModel.ItemRow>] = [KeyPathComparator(\.size, order: .reverse)]

    private var rows: [AppModel.ItemRow] { model.stats.filteredLargestRows }

    private var totalSize: Int64 {
        rows.reduce(Int64(0)) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)

            if rows.isEmpty {
                EmptyFolderView(
                    symbol: "tray",
                    title: "Ничего не найдено",
                    message: model.searchText.isEmpty
                        ? "Сканирование не нашло подходящих объектов."
                        : "Попробуйте изменить фильтр или сбросить категорию."
                )
            } else {
                table
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Крупнейшие объекты")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(Plural.items(rows.count)) · \(ByteFormat.string(totalSize))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if model.categoryFilter != nil {
                Text("Фильтр по типу включён")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            Text("Двойной клик — показать в Finder")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var table: some View {
        Table(rows, selection: $model.nav.selection, sortOrder: $sortOrder) {
            TableColumn("Имя", value: \.name) { row in
                HStack(spacing: 8) {
                    NodeIcon(category: row.category, isContainer: row.isContainer, size: 21)
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
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
            .width(min: 170, ideal: 260, max: 460)

            TableColumn("Где") { row in
                Text(folderLabel(row))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.path)
            }
            .width(min: 160, ideal: 340, max: 720)

            TableColumn("Размер", value: \.size) { row in
                Text(ByteFormat.string(row.size))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 96, max: 120)

            TableColumn("Доля", value: \.fraction) { row in
                Text(row.fraction.formatted(.percent.precision(.fractionLength(row.fraction < 0.01 ? 2 : 1))))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 64, max: 80)

            TableColumn("Тип") { row in
                HStack(spacing: 5) {
                    CategoryDot(category: row.category, size: 6)
                    Text(row.category == .app && row.isContainer ? "Приложение" : row.category.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
            model.inspector.previewSelection()
            return .handled
        }
        .contextMenu(forSelectionType: Int32.self) { selection in
            if let first = selection.first {
                let isContainer = model.tree?.node(first).nodeKind.isContainer == true
                Button("Открыть") { model.openRow(first) }
                Button("Показать в Finder") { model.reveal(indices: Array(selection)) }
                if !isContainer {
                    Button("Быстрый просмотр") { model.inspector.previewNode(first) }
                }
                Button("Копировать путь") { model.inspector.copyPaths(Array(selection)) }
                Button("Открыть в терминале") { model.inspector.openInTerminal(first) }
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
            }
        } primaryAction: { selection in
            if let first = selection.first {
                model.activateRow(first)
            }
        }
    }

    private func folderLabel(_ row: AppModel.ItemRow) -> String {
        let relative = row.relativePath
        guard let slash = relative.lastIndex(of: "/") else { return model.rootDisplayName }
        let folder = String(relative[..<slash])
        return folder.isEmpty ? model.rootDisplayName : folder
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("Приложения (.app) показаны одним объектом, их внутренности не участвуют в рейтинге.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Найдено \(ByteFormat.count(model.stats.largestItems.count)) объектов")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}
