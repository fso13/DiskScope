import SwiftUI

struct TypesView: View {
    @EnvironmentObject private var model: AppModel

    private var stats: [CategoryStat] { model.categoryStats }
    private var total: Int64 { max(model.tree?.totalSize ?? 0, 1) }
    private var largest: Int64 { max(stats.map(\.size).max() ?? 0, 1) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                distributionCard
                breakdownCard
                if !model.largestItems.isEmpty {
                    largestCard
                }
                note
            }
            .padding(.bottom, 10)
        }
    }

    private var distributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Распределение по типам")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Внутри «\(model.rootDisplayName)»")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteFormat.string(total))
                    .font(AppFont.number(17))
                    .monospacedDigit()
            }

            if stats.isEmpty {
                EmptyFolderView(
                    symbol: "chart.pie",
                    title: "Пока нечего показать",
                    message: "Просканируйте папку, чтобы увидеть распределение по типам."
                )
                .frame(height: 120)
            } else {
                CategoryBar(stats: stats, total: total)

                HStack(spacing: 16) {
                    ForEach(stats) { stat in
                        HStack(spacing: 5) {
                            CategoryDot(category: stat.category, size: 6)
                            Text(LocalizedStringKey(stat.category.title))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(ByteFormat.percent(stat.size, of: total))
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var breakdownCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Категории")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Нажмите на категорию, чтобы увидеть самые крупные файлы")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.border).frame(height: 1)

            ForEach(Array(stats.enumerated()), id: \.element.id) { offset, stat in
                CategoryRowView(
                    stat: stat,
                    total: total,
                    largest: largest
                ) {
                    model.showFiles(of: stat.category)
                }
                if offset < stats.count - 1 {
                    Rectangle().fill(Theme.border.opacity(0.65)).frame(height: 1).padding(.leading, 50)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var largestCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Крупнейшие объекты")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Нажмите, чтобы показать объект в Finder")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GhostButton(title: "Показать все", symbol: "arrow.right", tint: Theme.accent) {
                    model.tab = .largest
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.border).frame(height: 1)

            ForEach(model.largestItems.prefix(5)) { row in
                TopItemRow(row: row, rootName: model.rootDisplayName) {
                    model.reveal(indices: [row.id])
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("Пакеты .app считаются приложениями целиком. Файлы меньше 64 КБ объединены в «Другое» — это ускоряет сканирование и экономит память.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

private struct CategoryBar: View {
    let stats: [CategoryStat]
    let total: Int64

    var body: some View {
        GeometryReader { geometry in
            let gaps = CGFloat(max(stats.count - 1, 0)) * 2
            let available = max(geometry.size.width - gaps, 1)
            HStack(spacing: 2) {
                ForEach(stats) { stat in
                    let fraction = CGFloat(stat.size) / CGFloat(total)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.categoryColor(stat.category),
                                    Theme.categoryColor(stat.category).opacity(0.62),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: max(3, available * fraction))
                }
            }
        }
        .frame(height: 18)
    }
}

private struct CategoryRowView: View {
    let stat: CategoryStat
    let total: Int64
    let largest: Int64
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.categoryColor(stat.category).opacity(0.14))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: stat.category.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.categoryColor(stat.category))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(stat.category.title))
                        .font(.system(size: 12, weight: .medium))
                    Text(countLabel)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 14)

                ProgressBar(
                    fraction: Double(stat.size) / Double(largest),
                    tint: AnyShapeStyle(Theme.categoryColor(stat.category)),
                    height: 4
                )
                .frame(width: 140)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormat.string(stat.size))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                    Text(ByteFormat.percent(stat.size, of: total))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .frame(width: 86, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(hovering ? Theme.subtleFill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Показать файлы категории «\(stat.category.title)»")
    }

    private var countLabel: String {
        if stat.category == .app {
            return Plural.apps(stat.count)
        }
        return Plural.files(stat.count)
    }
}

private struct TopItemRow: View {
    @EnvironmentObject private var model: AppModel
    let row: AppModel.ItemRow
    let rootName: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                NodeIcon(category: row.category, isContainer: row.isContainer, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(row.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if row.isHardLink {
                            Image(systemName: "link")
                                .font(.system(size: 7.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .help("Жёсткая ссылка: размер уже учтён в другой записи")
                        }
                    }
                    Text(folderLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(ByteFormat.string(row.size))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(hovering ? Theme.subtleFill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(row.path)
        .contextMenu {
            Button("Открыть") { model.openRow(row.id) }
            Button("Показать в Finder") { model.reveal(indices: [row.id]) }
            if !row.isContainer {
                Button("Быстрый просмотр") { model.previewNode(row.id) }
            }
            Button("Копировать путь") { model.copyPaths([row.id]) }
            Button("Открыть в терминале") { model.openInTerminal(row.id) }
            Divider()
            Button(model.isInCollection(row.id) ? "Убрать из коллекции" : "В коллекцию") {
                model.toggleCollection([row.id])
            }
            Divider()
            Button("В Корзину…", role: .destructive) {
                model.selection = [row.id]
                model.requestTrashSelection()
            }
        }
    }

    private var folderLabel: String {
        let relative = row.relativePath
        guard let slash = relative.lastIndex(of: "/") else { return rootName }
        return String(relative[..<slash])
    }
}
