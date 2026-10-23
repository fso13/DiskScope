import SwiftUI

struct DiskOverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                capacityCard
                metrics
                trashCard
                snapshotsCard
                note
            }
            .padding(.bottom, 10)
        }
        .task {
            model.refreshDiskOverview()
        }
    }

    private var overview: DiskOverview? { model.disk.overview }

    private var capacityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(overview?.volume.name ?? model.internalVolume?.name ?? "Macintosh HD")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Занято, свободно и purgeable")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.refreshDiskOverview(force: true)
                } label: {
                    HStack(spacing: 5) {
                        if model.disk.loading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text("Обновить")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(model.disk.loading)
            }

            if let overview {
                Text(ByteFormat.percent(overview.usedBytes, of: overview.totalBytes))
                    .font(AppFont.number(34))
                    .monospacedDigit()

                capacityBar(overview)

                HStack(spacing: 18) {
                    legend("Данные", color: Theme.accent, value: max(overview.usedBytes - reclaimable(overview), 0))
                    legend("Purgeable", color: .purple, value: reclaimable(overview))
                    legend("Свободно", color: .green, value: overview.freeBytes)
                }
            } else if model.disk.loading {
                ProgressView("Считаем место…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Text(model.disk.error ?? "Нет данных о диске")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private func capacityBar(_ overview: DiskOverview) -> some View {
        GeometryReader { geometry in
            let total = max(Double(overview.totalBytes), 1)
            let purgeable = Double(reclaimable(overview)) / total
            let data = max(1 - Double(overview.freeBytes) / total - purgeable, 0)
            let free = Double(overview.freeBytes) / total
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: max(geometry.size.width * data, data > 0 ? 3 : 0))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.purple.opacity(0.8))
                    .frame(width: max(geometry.size.width * purgeable, purgeable > 0 ? 3 : 0))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.green.opacity(0.65))
                    .frame(width: max(geometry.size.width * free, free > 0 ? 3 : 0))
            }
        }
        .frame(height: 18)
    }

    private func legend(_ title: String, color: Color, value: Int64) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(ByteFormat.string(value))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metricCard(
                title: "Свободно",
                value: overview.map { ByteFormat.string($0.freeBytes) } ?? "—",
                detail: overview.map { L10n.isEnglish
                    ? "of \(ByteFormat.string($0.totalBytes))"
                    : "из \(ByteFormat.string($0.totalBytes))" } ?? "",
                symbol: "internaldrive",
                tint: .green
            )
            metricCard(
                title: "Можно освободить",
                value: overview.map { ByteFormat.string(reclaimable($0)) } ?? "—",
                detail: "purgeable",
                symbol: "arrow.down.circle",
                tint: .purple
            )
            metricCard(
                title: "Корзина",
                value: overview.map { ByteFormat.string($0.trash.size) } ?? "—",
                detail: overview.map { Plural.items($0.trash.items) } ?? "",
                symbol: "trash",
                tint: Theme.danger
            )
            metricCard(
                title: "Снимки APFS",
                value: overview.map { ByteFormat.count($0.snapshots.count) } ?? "—",
                detail: "локальные",
                symbol: "clock.arrow.circlepath",
                tint: Theme.accent
            )
        }
    }

    private func metricCard(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }

    private var trashCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Корзина")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Файлы, которые уже удалены, но ещё занимают место")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GhostButton(title: "Открыть Корзину", symbol: "arrow.up.forward.app") {
                    model.openTrash()
                }
            }
            if let overview {
                HStack(spacing: 16) {
                    Text(ByteFormat.string(overview.trash.size))
                        .font(AppFont.number(20))
                        .monospacedDigit()
                    Text(Plural.items(overview.trash.items))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(overview.trash.url.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
    }

    private var snapshotsCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Снимки APFS")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Локальные снимки Time Machine могут удерживать блоки")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(overview.map { ByteFormat.count($0.snapshots.count) } ?? "—")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.border).frame(height: 1)

            if let overview, !overview.snapshots.isEmpty {
                ForEach(overview.snapshots.prefix(12)) { snapshot in
                    HStack(spacing: 9) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(snapshot.name)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(snapshot.date.map {
                                $0.formatted(date: .abbreviated, time: .shortened)
                            } ?? "Дата неизвестна")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                if overview.snapshots.count > 12 {
                    Text("Ещё \(overview.snapshots.count - 12)…")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(snapshotEmptyText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
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
            Text(L10n.isEnglish
                ? "Purgeable is an estimate of space macOS can reclaim without deleting your files. "
                    + "APFS snapshots are not files and can pin blocks; DiskScope does not delete them. "
                    + "APFS clones are counted as separate files: deleting one clone may free nothing."
                : "Purgeable — оценка места, которое macOS может освободить без удаления ваших файлов. "
                    + "Снимки APFS не показываются как файлы и могут удерживать блоки; "
                    + "DiskScope их не удаляет. APFS-клоны учитываются как отдельные файлы: "
                    + "удаление одного клона может не освободить место.")
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func reclaimable(_ overview: DiskOverview) -> Int64 {
        min(overview.purgeableBytes, overview.usedBytes)
    }

    private var snapshotEmptyText: String {
        if model.disk.loading { return "Проверяем снимки…" }
        if let overview = model.disk.overview, !overview.snapshotsAvailable {
            return "Не удалось прочитать снимки через tmutil"
        }
        return "Локальных снимков нет"
    }
}
