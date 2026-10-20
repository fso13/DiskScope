import AppKit
import SwiftUI

struct MediaView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var media: MediaModel

    @State private var sortOrder: [KeyPathComparator<MediaFile>] = [
        KeyPathComparator(\.size, order: .reverse),
    ]
    @State private var showMoveConfirmation = false
    @State private var showPhotosConfirmation = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            queryPanel
                .frame(width: 304)

            resultsPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            media.seedCurrentFolder(model.tree?.rootPath)
        }
        .alert("Перенести файлы?", isPresented: $showMoveConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Перенести", role: .destructive) {
                media.moveSelected()
            }
        } message: {
            Text(
                "\(Plural.files(media.selectedFiles.count)) · \(ByteFormat.string(media.selectedSize)) будут перемещены в «\(media.destinationName)»."
            )
        }
        .alert("Импортировать в «Фото»?", isPresented: $showPhotosConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Импортировать", role: .destructive) {
                Task { await media.importSelectedToPhotos() }
            }
        } message: {
            Text(photosConfirmationMessage)
        }
        .alert("Нет доступа к «Фото»", isPresented: $media.showPhotosAccessAlert) {
            Button("Открыть настройки") { media.openPhotosSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Разрешите DiskScope доступ к «Фото» в разделе «Конфиденциальность и безопасность → Фото».")
        }
    }

    private var photosConfirmationMessage: String {
        let photos = media.selectedPhotosCount
        let selected = media.selectedFiles.count
        var text = "\(Plural.files(photos)) будут импортированы в «Фото». Оригиналы будут перемещены из исходных папок."
        if selected > photos {
            text += " Остальные выбранные файлы (\(selected - photos)) останутся на месте."
        }
        return text
    }

    // MARK: - Query panel

    private var queryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sourcesSection
                    separator
                    typesSection
                    separator
                    destinationSection
                    photosHint
                }
                .padding(14)
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            searchFooter
                .padding(14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var separator: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }

    private func sectionLabel(_ title: String, detail: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.tertiary)
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ПАПКИ ДЛЯ ПОИСКА", detail: "\(media.sources.count)")

            if media.sources.isEmpty {
                Text("Добавьте одну или несколько папок — поиск не зависит от текущего скана.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(media.sources, id: \.path) { url in
                        MediaSourceRow(
                            url: url,
                            homePath: model.homePath,
                            disabled: media.isBusy
                        ) {
                            media.removeSource(url)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                GhostButton(title: "Добавить…", symbol: "folder.badge.plus", tint: Theme.accent) {
                    media.chooseSources()
                }
                if let root = model.tree?.rootPath {
                    GhostButton(title: "Текущая", symbol: "scope", tint: .secondary) {
                        media.addCurrentFolder(root)
                    }
                    .help(root)
                }
                Spacer(minLength: 0)
            }
            .disabled(media.isBusy)
        }
    }

    private var typesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ТИПЫ ФАЙЛОВ", detail: "\(media.types.count)")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                ],
                spacing: 6
            ) {
                ForEach(MediaType.allCases) { type in
                    MediaTypeChip(
                        type: type,
                        isSelected: media.types.contains(type),
                        disabled: media.isBusy
                    ) {
                        media.toggleType(type)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Все") { media.selectAllTypes() }
                Button("Сбросить") { media.clearTypes() }
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.accent)
            .disabled(media.isBusy)
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("КУДА ПЕРЕНЕСТИ")

            Button {
                media.chooseDestination()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.destinationName.isEmpty ? "Выберите папку" : media.destinationName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !media.destinationPath.isEmpty {
                            Text(abbreviate(media.destinationPath))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(media.isMoving || media.isImportingToPhotos)
            .help(media.destinationPath.isEmpty ? "Выберите папку назначения" : media.destinationPath)

            Text("Совпадающие имена получат суффикс « 2», « 3»…")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var photosHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 9, weight: .semibold))
                Text("В «Фото»")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)

            Text("Импортируются JPG, PNG, HEIC, TIFF, RAW и другие растровые изображения. PSD, AI и SVG останутся в папке.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Theme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.12), lineWidth: 1)
        )
    }

    private var searchFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if media.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Ищу файлы…")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 4)
                    Button("Отменить") { media.cancelSearch() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }

                if let progress = media.progress {
                    Text("Просмотрено \(ByteFormat.count(progress.scanned)) · найдено \(ByteFormat.count(progress.matched))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(abbreviate(progress.currentPath.isEmpty ? "…" : progress.currentPath))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if let progress = media.moveProgress {
                operationProgress(progress, title: "Переношу файлы")
            } else if let progress = media.photosProgress {
                operationProgress(progress, title: "Импортирую в «Фото»")
            } else {
                MediaActionButton(
                    title: "Найти файлы",
                    symbol: "magnifyingglass",
                    prominent: true,
                    fullWidth: true,
                    disabled: !media.canSearch,
                    help: media.canSearch ? "Начать поиск" : searchHint
                ) {
                    media.search()
                }

                Text(searchHint)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchHint: String {
        if media.sources.isEmpty { return "Сначала добавьте хотя бы одну папку." }
        if media.types.isEmpty { return "Выберите хотя бы один тип файлов." }
        if media.isBusy { return "Дождитесь завершения операции." }
        return "Поиск идёт по выбранным папкам и не меняет файлы."
    }

    private func operationProgress(_ progress: MediaModel.OperationProgress, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(progress.done) / \(progress.total)")
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressBar(fraction: progress.fraction, height: 5)
        }
    }

    // MARK: - Results

    private var resultsPanel: some View {
        VStack(spacing: 0) {
            resultsHeader
            Rectangle().fill(Theme.border).frame(height: 1)
            resultsContent
            if media.truncated || media.skippedItems > 0 {
                notices
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var resultsHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Найденные файлы")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(resultsSummary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 6)
            SearchField(text: $media.resultFilter, placeholder: "Фильтр по имени", width: 170)
            Button("Выбрать все") { media.selectAllFiltered() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.accent)
                .disabled(media.filteredResults.isEmpty)
            Button("Снять") { media.clearSelection() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .disabled(media.selectedIDs.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var resultsSummary: String {
        guard media.hasSearched else { return "Поиск по выбранным папкам" }
        if media.filteredResults.count == media.results.count {
            return "\(Plural.files(media.results.count)) · \(ByteFormat.string(media.resultsBytes))"
        }
        return "\(Plural.files(media.filteredResults.count)) из \(ByteFormat.count(media.results.count)) · \(ByteFormat.string(media.filteredBytes))"
    }

    @ViewBuilder
    private var resultsContent: some View {
        if media.isSearching {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Сканирую выбранные папки…")
                    .font(.system(size: 12, weight: .semibold))
                if let progress = media.progress {
                    Text("Просмотрено \(ByteFormat.count(progress.scanned)) · найдено \(ByteFormat.count(progress.matched))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(abbreviate(progress.currentPath.isEmpty ? "…" : progress.currentPath))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 20)
                }
                Button("Отменить поиск") { media.cancelSearch() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !media.hasSearched {
            EmptyFolderView(
                symbol: "photo.on.rectangle.angled",
                title: "Медиа-поиск",
                message: "Добавьте папки, выберите типы и нажмите «Найти файлы». Найденное можно перенести в папку или в «Фото»."
            )
        } else if media.filteredResults.isEmpty {
            EmptyFolderView(
                symbol: "magnifyingglass",
                title: "Ничего не найдено",
                message: media.resultFilter.isEmpty
                    ? "Попробуйте другие папки или типы файлов."
                    : "Попробуйте изменить фильтр по имени."
            )
        } else {
            resultsTable
        }
    }

    private var resultsTable: some View {
        Table(media.filteredResults, selection: $media.selectedIDs, sortOrder: $sortOrder) {
            TableColumn("") { file in
                Toggle(
                    "",
                    isOn: Binding(
                        get: { media.selectedIDs.contains(file.id) },
                        set: { isSelected in
                            if isSelected {
                                media.selectedIDs.insert(file.id)
                            } else {
                                media.selectedIDs.remove(file.id)
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .width(24)

            TableColumn("Файл", value: \.name) { file in
                HStack(spacing: 8) {
                    NodeIcon(category: file.kind.category, isContainer: false, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(folderLabel(file))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .help(file.path)
            }
            .width(min: 210, ideal: 330, max: 560)

            TableColumn("Тип") { file in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.categoryColor(file.kind.category))
                        .frame(width: 6, height: 6)
                    Text(file.kind.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 78, ideal: 98, max: 120)

            TableColumn("Размер", value: \.size) { file in
                Text(ByteFormat.string(file.size))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 78, ideal: 94, max: 115)

            TableColumn("Изменён") { file in
                Text(file.modified?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 78, ideal: 94, max: 115)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: MediaFile.ID.self) { selection in
            if !selection.isEmpty {
                Button("Открыть") { openFiles(Array(selection)) }
                Button("Показать в Finder") { revealFiles(Array(selection)) }
                Divider()
                Button("Снять выбор") { media.selectedIDs.subtract(selection) }
            }
        } primaryAction: { selection in
            if let first = selection.first {
                openFiles([first])
            }
        }
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: 4) {
            if media.truncated {
                notice(
                    "Показаны первые \(ByteFormat.count(media.results.count)) файлов. Уточните папки или типы.",
                    symbol: "exclamationmark.triangle.fill",
                    tint: Theme.warning
                )
            }
            if media.skippedItems > 0 {
                notice(
                    "\(media.skippedItems) объектов пропущено из-за прав доступа.",
                    symbol: "lock.fill",
                    tint: Theme.warning
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func notice(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5))
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Выбрано: \(Plural.files(media.selectedFiles.count))")
                    .font(.system(size: 10.5, weight: .medium))
                if !media.selectedIDs.isEmpty {
                    Text(ByteFormat.string(media.selectedSize))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            if media.selectedImageCount > 0 {
                MediaActionButton(
                    title: "В Фото \(media.selectedPhotosCount)",
                    symbol: "photo.on.rectangle.angled",
                    prominent: false,
                    disabled: !media.canImportToPhotos,
                    help: media.selectedPhotosCount == 0
                        ? "Выбранные изображения не поддерживаются «Фото»"
                        : "Импортировать выбранные изображения в «Фото»"
                ) {
                    showPhotosConfirmation = true
                }
            }

            MediaActionButton(
                title: media.selectedFiles.isEmpty
                    ? "Перенести"
                    : "Перенести \(media.selectedFiles.count)",
                symbol: "arrow.right.circle.fill",
                prominent: true,
                disabled: !media.canMove,
                help: media.destination == nil
                    ? "Сначала выберите папку назначения"
                    : "Переместить выбранные файлы"
            ) {
                showMoveConfirmation = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func folderLabel(_ file: MediaFile) -> String {
        if !file.relativePath.isEmpty {
            let parent = (file.relativePath as NSString).deletingLastPathComponent
            if !parent.isEmpty { return parent }
        }
        return abbreviate(file.sourceRoot)
    }

    private func abbreviate(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        if path == model.homePath { return "~" }
        if path.hasPrefix(model.homePath + "/") {
            return "~" + path.dropFirst(model.homePath.count)
        }
        return path
    }

    private func file(for id: MediaFile.ID) -> MediaFile? {
        media.results.first { $0.id == id }
    }

    private func openFiles(_ ids: [MediaFile.ID]) {
        for id in ids {
            if let file = file(for: id) {
                NSWorkspace.shared.open(file.url)
            }
        }
    }

    private func revealFiles(_ ids: [MediaFile.ID]) {
        let urls = ids.compactMap { file(for: $0)?.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

private struct MediaSourceRow: View {
    let url: URL
    let homePath: String
    let disabled: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(shortPath)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Theme.subtleFill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .help("Убрать папку")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .help(url.path)
    }

    private var displayName: String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private var shortPath: String {
        if url.path == homePath { return "~" }
        if url.path.hasPrefix(homePath + "/") {
            return "~" + url.path.dropFirst(homePath.count)
        }
        return url.path
    }
}

private struct MediaTypeChip: View {
    let type: MediaType
    let isSelected: Bool
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: type.symbolName)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(type.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : (hovering ? Theme.subtleFill : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.36) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .onHover { hovering = $0 }
    }
}

private struct MediaActionButton: View {
    let title: String
    let symbol: String
    let prominent: Bool
    var fullWidth = false
    var disabled = false
    var help = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .overlay(
                Capsule()
                    .strokeBorder(
                        prominent ? Color.white.opacity(0.16) : (hovering && !disabled ? Theme.accent.opacity(0.4) : Theme.border),
                        lineWidth: 1
                    )
            )
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help)
    }

    private var textColor: Color {
        if prominent { return .white }
        return disabled ? .secondary : .primary
    }

    @ViewBuilder
    private var background: some View {
        if prominent {
            Capsule().fill(
                LinearGradient(
                    colors: [Theme.accent, Theme.accentDeep],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        } else {
            Capsule().fill(Theme.subtleFill)
        }
    }
}
