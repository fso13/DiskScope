import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var rows: [AppModel.ItemRow] { model.collectionRows }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)

            if rows.isEmpty {
                EmptyFolderView(
                    symbol: "tray",
                    title: "Коллекция пуста",
                    message: "Добавляйте файлы и папки из разных мест через контекстное меню, "
                        + "кнопку в карточке на карте или ⌘-клик по ячейке."
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(rows) { row in
                            CollectionRow(
                                row: row,
                                onReveal: { model.browser.reveal(indices: [row.id]) },
                                onRemove: { model.removeFromCollection([row.id]) }
                            )
                        }
                    }
                    .padding(12)
                }
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 680, height: 570)
        .background(Theme.background)
        .alert("Переместить коллекцию в Корзину?", isPresented: $model.trash.showCollectionConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("В Корзину", role: .destructive) { model.trashOperations.confirmCollection() }
        } message: {
            Text(model.collectionTrashMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Коллекция")
                    .font(.system(size: 20, weight: .semibold))
                Text("\(Plural.items(model.collectionCount)) · \(ByteFormat.string(model.collectionSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.subtleFill, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Закрыть")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            GhostButton(title: "Очистить", symbol: "xmark.circle") {
                model.clearCollection()
            }
            .disabled(rows.isEmpty)

            Spacer()

            AccentButton(title: "В Корзину…", symbol: "trash") {
                model.trashOperations.requestCollection()
            }
            .disabled(!model.trashOperations.canTrashCollection)
            .opacity(model.trashOperations.canTrashCollection ? 1 : 0.45)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct CollectionRow: View {
    let row: AppModel.ItemRow
    let onReveal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NodeIcon(category: row.category, isContainer: row.isContainer, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.relativePath.isEmpty ? row.path : row.relativePath)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.path)
            }

            Spacer(minLength: 8)

            Text(ByteFormat.string(row.size))
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()

            IconActionButton(symbol: "magnifyingglass", help: "Показать в Finder", action: onReveal)
            IconActionButton(
                symbol: "minus.circle",
                help: "Убрать из коллекции",
                tint: Theme.danger,
                action: onRemove
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.subtleFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}
