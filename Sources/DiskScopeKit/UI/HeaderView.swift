import AppKit
import SwiftUI

struct HeaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if showsFileChrome {
                breadcrumbs
            }

            HStack(alignment: .center, spacing: 16) {
                titleBlock
                Spacer(minLength: 12)
                if showsFileChrome {
                    actions
                }
            }

            HStack(spacing: 10) {
                SegmentedTabs(selection: $model.tab)
                Spacer(minLength: 8)
                if model.tab == .map || model.tab == .largest {
                    SearchField(text: $model.searchText)
                }
                if showsFileChrome, let filter = model.categoryFilter {
                    CategoryFilterChip(category: filter) {
                        model.clearCategoryFilter()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var showsFileChrome: Bool {
        model.tab != .media && model.tab != .cleanup && model.tab != .disk
            && model.tab != .duplicates && model.tab != .similar
    }

    // MARK: - Breadcrumbs

    private var breadcrumbs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(model.breadcrumbs.enumerated()), id: \.element) { offset, index in
                        if offset > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 1)
                        }
                        crumb(index)
                            .id(index)
                    }
                }
                .padding(.vertical, 1)
            }
            .onAppear {
                proxy.scrollTo(model.currentIndex, anchor: .trailing)
            }
            .onChange(of: model.currentIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .trailing)
                }
            }
        }
        .frame(height: 18)
    }

    private func crumb(_ index: Int32) -> some View {
        let isLast = index == model.currentIndex
        return Button {
            model.navigate(to: index)
        } label: {
            HStack(spacing: 4) {
                if index == 0 {
                    Image(systemName: rootSymbol)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(crumbTitle(index))
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: isLast ? .semibold : .medium))
            .foregroundStyle(isLast ? Color.primary : Color.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                if isLast {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.subtleFill)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLast)
        .help(model.tree?.path(of: index) ?? "")
    }

    private var rootSymbol: String {
        guard let path = model.tree?.rootPath else { return "internaldrive.fill" }
        if path == "/" { return "internaldrive.fill" }
        if path == model.homePath { return "house.fill" }
        return "folder.fill"
    }

    private func crumbTitle(_ index: Int32) -> String {
        if index == 0 { return model.rootDisplayName }
        guard let tree = model.tree else { return "" }
        let name = tree.name(of: index)
        return name.isEmpty ? "…" : name
    }

    // MARK: - Title

    @ViewBuilder
    private var titleBlock: some View {
        if model.tab == .media {
            VStack(alignment: .leading, spacing: 6) {
                Text("Медиа")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.4)
                Text("Поиск файлов по типам и перенос в папку или «Фото»")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if model.tab == .cleanup {
            VStack(alignment: .leading, spacing: 6) {
                Text("Очистка")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.4)
                Text("Кэши, установщики и бэкапы, которые можно удалить без перескана")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if model.tab == .disk {
            VStack(alignment: .leading, spacing: 6) {
                Text("Диск")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.4)
                Text("Свободное место, purgeable, снимки APFS и Корзина")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if model.tab == .duplicates {
            VStack(alignment: .leading, spacing: 6) {
                Text("Дубликаты")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.4)
                Text("Одинаковые файлы по содержимому — с учётом жёстких ссылок")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if model.tab == .similar {
            VStack(alignment: .leading, spacing: 6) {
                Text("Похожие изображения")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.4)
                Text("Локальный Vision: признаки кадров, без сети")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.currentName)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.4)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    StatPill(symbol: "internaldrive", text: ByteFormat.string(model.currentSize))
                    StatPill(symbol: "doc.on.doc", text: Plural.files(model.currentItemCount))
                    StatPill(symbol: "square.stack.3d.up", text: Plural.elements(model.currentDirectCount))
                    if model.currentIndex != 0, let tree = model.tree {
                        Text("\(ByteFormat.percent(model.currentSize, of: tree.totalSize)) от скана")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 5) {
            Menu {
                Button("Сканировать снова") { model.rescan() }
                Button("Текущую папку") { model.scan(path: model.currentPath) }
                    .disabled(model.currentIndex == 0)
                Divider()
                Button("Домашняя папка") { model.scanHome() }
                Button("Вся система") { model.scan(path: "/") }
                Button("Выбрать папку…") { model.chooseFolder() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text("Сканировать")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .opacity(0.65)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentDeep],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: Theme.accent.opacity(0.32), radius: 8, y: 3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Сканировать (⌘R)")

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 3)

            IconActionButton(symbol: "arrow.up", help: "Наверх (⌘↑)", disabled: !model.canGoUp) {
                model.goUp()
            }

            IconActionButton(
                symbol: "magnifyingglass",
                help: model.selection.isEmpty
                    ? "Показать папку в Finder (⇧⌘R)"
                    : "Показать выбранное в Finder (⇧⌘R)"
            ) {
                if model.selection.isEmpty {
                    model.revealCurrentFolder()
                } else {
                    model.revealSelection()
                }
            }

            IconActionButton(
                symbol: "sidebar.right",
                help: "Инспектор (⌥⌘I)",
                tint: model.showInspector ? Theme.accent : .primary
            ) {
                model.showInspector.toggle()
            }

            IconActionButton(
                symbol: "tray.full",
                help: model.collectionCount == 0
                    ? "Коллекция"
                    : "Коллекция: \(model.collectionSummary)",
                tint: model.collectionCount > 0 ? Theme.accent : .primary
            ) {
                model.showCollection = true
            }

            IconActionButton(
                symbol: "trash",
                help: "Переместить в Корзину (⌘⌫)",
                tint: Theme.danger,
                disabled: !model.canTrashSelection
            ) {
                model.requestTrashSelection()
            }
        }
    }
}
