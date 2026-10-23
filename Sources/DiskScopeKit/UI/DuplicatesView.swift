import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: Set<Int32> = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                controlCard
                if model.duplicates.scanning {
                    progressCard
                } else if model.duplicates.groups.isEmpty {
                    emptyCard
                } else {
                    ForEach(model.duplicates.groups) { group in
                        DuplicateGroupCard(group: group, selected: $selected)
                            .environmentObject(model)
                    }
                    if model.duplicates.groups.count >= 300 {
                        Text("Показаны первые 300 групп. Увеличьте минимальный размер, чтобы сузить выборку.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                note
            }
            .padding(.bottom, 10)
        }
        .task {
            model.findDuplicates()
        }
        .onChange(of: model.duplicates.groups) { _, _ in
            seedSelection()
        }
        .onChange(of: model.duplicates.minimumSize) { _, _ in
            model.findDuplicates(force: true)
        }
        .onAppear {
            seedSelection()
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Одинаковые файлы")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Сначала по размеру, затем по частичному и полному SHA-256")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.findDuplicates(force: true)
                } label: {
                    HStack(spacing: 5) {
                        if model.duplicates.scanning {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(model.duplicates.scanning ? "Ищем…" : "Найти")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(model.duplicates.scanning || model.tree == nil)
            }

            HStack(spacing: 12) {
                Picker("Минимальный размер", selection: $model.duplicates.minimumSize) {
                    Text("Любой размер").tag(Int64(0))
                    Text("от 1 МБ").tag(Int64(1_000_000))
                    Text("от 10 МБ").tag(Int64(10_000_000))
                    Text("от 100 МБ").tag(Int64(100_000_000))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 145)

                if !model.duplicates.groups.isEmpty {
                    statPill("Групп", ByteFormat.count(model.duplicates.groups.count))
                    statPill("Кандидатов", ByteFormat.count(model.duplicates.candidateCount))
                    statPill("Можно освободить", ByteFormat.string(model.duplicates.totalWasted), tint: Theme.accent)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private func statPill(_ title: String, _ value: String, tint: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Считаем хеши")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(model.duplicates.progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressBar(
                fraction: model.duplicates.progress,
                tint: AnyShapeStyle(Theme.accent),
                height: 6
            )
            Text("Файлы читаются локально; содержимое никуда не отправляется.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var emptyCard: some View {
        EmptyFolderView(
            symbol: model.tree == nil ? "doc.on.doc" : "checkmark.circle",
            title: model.tree == nil ? "Сначала просканируйте папку" : "Дубликатов не найдено",
            message: model.tree == nil
                ? "Поиск работает по текущему скану."
                : "Файлов одинакового размера и содержимого выше порога нет."
        )
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(L10n.isEnglish
                ? "Hard links are not duplicates: they share the same blocks. "
                    + "By default every copy except the first is selected; uncheck the ones you want to keep."
                : "Жёсткие ссылки не считаются дубликатами: это те же блоки. "
                    + "По умолчанию в каждой группе выбраны все копии, кроме первой; "
                    + "снимите отметки, чтобы оставить нужные файлы.")
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func seedSelection() {
        var next: Set<Int32> = []
        for group in model.duplicates.groups {
            for file in group.files.dropFirst() {
                next.insert(file.index)
            }
        }
        selected = next
    }
}

private struct DuplicateGroupCard: View {
    @EnvironmentObject private var model: AppModel
    let group: DuplicateGroup
    @Binding var selected: Set<Int32>

    private var groupSelection: Set<Int32> {
        Set(group.files.map(\.index)).intersection(selected)
    }

    private var selectedBytes: Int64 {
        group.size * Int64(groupSelection.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            ForEach(group.files) { file in
                row(file)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ByteFormat.string(group.size)) · \(Plural.items(group.files.count))")
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.isEnglish
                    ? "Potentially frees \(ByteFormat.string(group.wastedBytes))"
                    : "Потенциально освободит \(ByteFormat.string(group.wastedBytes))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GhostButton(title: "Оставить одну", symbol: "checkmark.circle") {
                let indices = group.files.map(\.index)
                selected.subtract(indices)
                for file in group.files.dropFirst() { selected.insert(file.index) }
            }
            GhostButton(title: "В коллекцию", symbol: "tray.full") {
                model.collectDuplicateFiles(Set(group.files.map(\.index)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(_ file: DuplicateFile) -> some View {
        HStack(spacing: 9) {
            Button {
                if selected.contains(file.index) {
                    selected.remove(file.index)
                } else {
                    selected.insert(file.index)
                }
            } label: {
                Image(systemName: selected.contains(file.index) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected.contains(file.index) ? Theme.accent : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            NodeIcon(category: fileCategory(file), isContainer: false, size: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text((file.path as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.relativePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
            }

            Spacer(minLength: 6)

            Text(file.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)

            IconActionButton(symbol: "magnifyingglass", help: "Показать в Finder") {
                model.reveal(indices: [file.index])
            }
            IconActionButton(symbol: "eye", help: "Быстрый просмотр") {
                model.inspector.previewNode(file.index)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func fileCategory(_ file: DuplicateFile) -> FileCategory {
        FileCategory.forExtension((file.path as NSString).pathExtension)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(L10n.isEnglish
                ? (groupSelection.isEmpty
                    ? "Nothing selected"
                    : "Selected: \(groupSelection.count) · \(ByteFormat.string(selectedBytes))")
                : (groupSelection.isEmpty
                    ? "Ничего не выбрано"
                    : "Выбрано: \(groupSelection.count) · \(ByteFormat.string(selectedBytes))"))
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            Spacer()
            AccentButton(title: "В Корзину…", symbol: "trash") {
                model.trashDuplicateFiles(groupSelection)
            }
            .disabled(groupSelection.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
