import AppKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI

struct SimilarImagesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: Set<Int32> = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                controlCard
                if model.similar.state.scanning {
                    progressCard
                } else if model.similar.state.groups.isEmpty {
                    emptyCard
                } else {
                    ForEach(model.similar.state.groups) { group in
                        SimilarGroupCard(group: group, selected: $selected)
                            .environmentObject(model)
                    }
                }
                note
            }
            .padding(.bottom, 10)
        }
        .task { model.findSimilarImages() }
        .onChange(of: model.similar.state.groups) { _, _ in selected = [] }
        .onChange(of: model.similar.options) { _, _ in
            model.findSimilarImages(force: true)
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Похожие изображения")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Vision сравнивает признаки локально — без сети и облака")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.findSimilarImages(force: true)
                } label: {
                    HStack(spacing: 5) {
                        if model.similar.state.scanning {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(model.similar.state.scanning ? "Ищем…" : "Найти")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(model.similar.state.scanning || model.tree == nil)
            }

            HStack(spacing: 12) {
                Picker("Порог", selection: $model.similar.options.threshold) {
                    Text("Строже").tag(Float(0.2))
                    Text("Обычно").tag(Float(0.35))
                    Text("Шире").tag(Float(0.5))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 110)

                Picker("Размер", selection: $model.similar.options.minimumSize) {
                    Text("от 100 КБ").tag(Int64(100_000))
                    Text("от 1 МБ").tag(Int64(1_000_000))
                    Text("от 10 МБ").tag(Int64(10_000_000))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 120)

                if !model.similar.state.groups.isEmpty {
                    statPill("Групп", ByteFormat.count(model.similar.state.groups.count))
                    statPill("Просмотрено", ByteFormat.count(model.similar.state.scannedCount))
                    statPill("Кандидатов", ByteFormat.count(model.similar.state.candidateCount))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private func statPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Считаем признаки изображений")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(model.similar.state.progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressBar(
                fraction: model.similar.state.progress,
                tint: AnyShapeStyle(Theme.accent),
                height: 6
            )
            Text("Изображения читаются локально; результаты не сохраняются.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var emptyCard: some View {
        EmptyFolderView(
            symbol: model.tree == nil ? "photo.stack" : "checkmark.circle",
            title: model.tree == nil ? "Сначала просканируйте папку" : "Похожих изображений не найдено",
            message: model.tree == nil
                ? "Поиск работает по текущему скану."
                : "Попробуйте «Шире» или меньший порог размера."
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
                ? "Similar is not identical: these shots have close features. "
                    + "Review previews before deleting. Hard links and packages are skipped."
                : "Похожие — не значит идентичные: это кадры с близкими признаками. "
                    + "Просматривайте превью перед удалением. Жёсткие ссылки и пакеты пропускаются.")
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

private struct SimilarGroupCard: View {
    @EnvironmentObject private var model: AppModel
    let group: SimilarImageGroup
    @Binding var selected: Set<Int32>

    private var groupSelection: Set<Int32> {
        Set(group.images.map(\.index)).intersection(selected)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            ForEach(group.images) { image in
                row(image)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Plural.items(group.images.count)) · \(ByteFormat.string(group.totalSize))")
                    .font(.system(size: 12, weight: .semibold))
                Text("Похожие кадры, не обязательно копии")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GhostButton(title: "Выбрать копии", symbol: "checkmark.circle") {
                selected.subtract(group.images.map(\.index))
                for image in group.images.dropFirst() { selected.insert(image.index) }
            }
            GhostButton(title: "В коллекцию", symbol: "tray.full") {
                model.collectSimilarImages(Set(group.images.map(\.index)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(_ image: SimilarImage) -> some View {
        HStack(spacing: 9) {
            Button {
                if selected.contains(image.index) {
                    selected.remove(image.index)
                } else {
                    selected.insert(image.index)
                }
            } label: {
                Image(systemName: selected.contains(image.index) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected.contains(image.index) ? Theme.accent : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            SimilarThumbnail(url: URL(fileURLWithPath: image.path))

            VStack(alignment: .leading, spacing: 1) {
                Text((image.path as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(image.relativePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(image.path)
            }

            Spacer(minLength: 6)

            Text(ByteFormat.string(image.size))
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()

            Text(image.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)

            IconActionButton(symbol: "magnifyingglass", help: "Показать в Finder") {
                model.reveal(indices: [image.index])
            }
            IconActionButton(symbol: "eye", help: "Быстрый просмотр") {
                model.previewNode(image.index)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(L10n.isEnglish
                ? (groupSelection.isEmpty
                    ? "Nothing selected"
                    : "Selected: \(groupSelection.count)")
                : (groupSelection.isEmpty
                    ? "Ничего не выбрано"
                    : "Выбрано: \(groupSelection.count)"))
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            Spacer()
            AccentButton(title: "В Корзину…", symbol: "trash") {
                model.trashSimilarImages(groupSelection)
            }
            .disabled(groupSelection.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct SimilarThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.subtleFill)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: url) {
            if image == nil {
                image = Self.downsample(url)
            }
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 100, height: 100),
                scale: 2,
                representationTypes: .thumbnail
            )
            let thumbnail: NSImage? = await withCheckedContinuation { continuation in
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                    continuation.resume(returning: representation?.nsImage)
                }
            }
            if let thumbnail {
                image = thumbnail
            } else if image == nil {
                image = Self.downsample(url)
            }
        }
    }

    private static func downsample(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 100,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
