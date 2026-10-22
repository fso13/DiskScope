import Foundation
import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String {
        model.globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            filters
            Rectangle().fill(Theme.border).frame(height: 1)
            results
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 900, height: 650)
        .background(Theme.background)
        .onAppear {
            model.ensureSearchIndex()
            searchFocused = true
        }
        .onExitCommand {
            model.showGlobalSearch = false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)

            TextField("Имя файла или часть пути…", text: $model.globalSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .focused($searchFocused)

            if !model.globalSearchText.isEmpty {
                Button {
                    model.globalSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Очистить")
            }

            Button {
                model.showGlobalSearch = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.subtleFill, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Закрыть (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var filters: some View {
        HStack(spacing: 9) {
            Picker("Размер", selection: $model.searchMinimumSize) {
                Text("Любой размер").tag(Int64(0))
                Text("> 100 МБ").tag(Int64(100_000_000))
                Text("> 1 ГБ").tag(Int64(1_000_000_000))
                Text("> 10 ГБ").tag(Int64(10_000_000_000))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)

            Picker("Тип", selection: $model.searchKind) {
                ForEach(SearchKind.allCases) { kind in
                    Text(LocalizedStringKey(kind.title)).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 100)

            Menu {
                Button("Любая категория") { model.searchCategory = nil }
                Divider()
                ForEach(FileCategory.allCases) { category in
                    Button(category.title) { model.searchCategory = category }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "tag")
                        .font(.system(size: 9, weight: .semibold))
                    Text(model.searchCategory?.title ?? "Категория")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.subtleFill, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Picker("Дата", selection: $model.searchDateRange) {
                ForEach(SearchDateRange.allCases) { range in
                    Text(LocalizedStringKey(range.title)).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 125)

            Spacer(minLength: 4)

            Picker("Сортировка", selection: $model.searchSort) {
                ForEach(SearchSort.allCases) { sort in
                    Text(LocalizedStringKey(sort.title)).tag(sort)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 120)

            Button("Сбросить") {
                model.globalSearchText = ""
                model.searchMinimumSize = 0
                model.searchCategory = nil
                model.searchKind = .any
                model.searchDateRange = .any
                model.searchSort = .size
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var results: some View {
        if model.searchIndexing {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Индексируем скан…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if trimmedQuery.isEmpty {
            EmptyFolderView(
                symbol: "magnifyingglass",
                title: "Найдите что угодно",
                message: "Имя файла или часть пути. Фильтры по размеру, типу, категории и дате помогают сузить выбор."
            )
        } else if model.searchHits.isEmpty {
            EmptyFolderView(
                symbol: "questionmark.folder",
                title: "Ничего не найдено",
                message: "Попробуйте другое имя, часть пути или ослабьте фильтры."
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(model.searchHits) { hit in
                        SearchResultRow(
                            hit: hit,
                            query: trimmedQuery,
                            onOpen: { model.navigateToSearchHit(hit) },
                            onReveal: { model.revealSearchHit(hit) },
                            onCollect: { model.addSearchHitToCollection(hit) },
                            onTrash: { model.requestTrashSearchHit(hit) }
                        )
                    }
                }
                .padding(10)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.searchTotal > 0 {
                Text("Найдено: \(ByteFormat.count(model.searchTotal))")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if model.searchTotal > model.searchHits.count {
                    Text("· показаны первые \(model.searchHits.count)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Поиск идёт по текущему скану и не покидает Mac")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("⌘F — поиск · Esc — закрыть")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct SearchResultRow: View {
    let hit: SearchHit
    let query: String
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCollect: () -> Void
    let onTrash: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NodeIcon(category: hit.category, isContainer: hit.kind.isContainer, size: 27)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    highlightedName
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if hit.isHardLink {
                        Image(systemName: "link")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .help("Жёсткая ссылка: размер уже учтён в другой записи")
                    }
                }
                Text(hit.relativePath.isEmpty ? hit.path : hit.relativePath)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(hit.path)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onOpen)

            Spacer(minLength: 8)

            Text(ByteFormat.string(hit.size))
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()

            Text(hit.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)

            IconActionButton(symbol: "arrow.up.right", help: "Перейти (двойной клик)", action: onOpen)
            IconActionButton(symbol: "magnifyingglass", help: "Показать в Finder", action: onReveal)
            IconActionButton(symbol: "tray.full", help: "В коллекцию", action: onCollect)
            IconActionButton(symbol: "trash", help: "В Корзину", tint: Theme.danger, action: onTrash)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.subtleFill.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .contextMenu {
            Button("Перейти") { onOpen() }
            Button("Показать в Finder") { onReveal() }
            Button("В коллекцию") { onCollect() }
            Divider()
            Button("В Корзину…", role: .destructive) { onTrash() }
        }
    }

    private var highlightedName: Text {
        var attributed = AttributedString(hit.name)
        guard !query.isEmpty,
              let range = hit.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
              let lower = AttributedString.Index(range.lowerBound, within: attributed),
              let upper = AttributedString.Index(range.upperBound, within: attributed) else {
            return Text(attributed)
        }
        attributed[lower..<upper].backgroundColor = Theme.accent.opacity(0.28)
        attributed[lower..<upper].foregroundColor = Color.primary
        return Text(attributed)
    }
}
