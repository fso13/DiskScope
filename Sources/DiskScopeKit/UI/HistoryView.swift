import Foundation
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedID: UUID?
    @State private var showClearConfirmation = false

    private var selected: ScanHistoryEntry? {
        if let selectedID, let entry = model.scanHistory.first(where: { $0.id == selectedID }) {
            return entry
        }
        return model.scanHistory.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)

            if model.scanHistory.isEmpty {
                EmptyFolderView(
                    symbol: "clock.arrow.circlepath",
                    title: "История пока пуста",
                    message: "Каждый скан сохраняется локально. После второго скана здесь появится сравнение «что выросло»."
                )
            } else {
                HStack(spacing: 0) {
                    historyList
                        .frame(width: 300)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    detail
                }
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 840, height: 580)
        .background(Theme.background)
        .onAppear {
            model.reloadHistory()
            if selectedID == nil { selectedID = model.scanHistory.first?.id }
        }
        .onExitCommand { model.showHistory = false }
        .alert("Очистить историю сканов?", isPresented: $showClearConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) {
                model.clearHistory()
                selectedID = nil
            }
        } message: {
            Text("Будут удалены все сохранённые точки сравнения. Сами файлы не затрагиваются.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("История сканов")
                    .font(.system(size: 16, weight: .semibold))
                Text("Сравните текущий скан с прошлым — что выросло")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.showHistory = false
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
        .padding(.vertical, 13)
    }

    private var historyList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                ForEach(model.scanHistory) { entry in
                    historyRow(entry)
                }
            }
            .padding(10)
        }
    }

    private func historyRow(_ entry: ScanHistoryEntry) -> some View {
        Button {
            selectedID = entry.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(entry.rootName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(ByteFormat.string(entry.totalSize))
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                }
                Text(entry.rootPath)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(Plural.files(entry.fileCount))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
            .padding(9)
            .background(
                selected?.id == entry.id ? Theme.accent.opacity(0.13) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected?.id == entry.id ? Theme.accent.opacity(0.3) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Сканировать снова") { model.rescanHistory(entry) }
            Divider()
            Button("Удалить запись", role: .destructive) { model.deleteHistory(entry) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            let diff = model.historyDiff(for: selected)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    detailHeader(selected, diff: diff)
                    if diff.hasCurrent, diff.comparable {
                        deltaCard(diff)
                        changesCard(diff)
                    } else {
                        unavailable(diff)
                    }
                    actions(selected)
                }
                .padding(16)
            }
        } else {
            EmptyFolderView(
                symbol: "clock",
                title: "Выберите скан",
                message: "Слева — сохранённые точки. Справа появится сравнение с текущим сканом."
            )
        }
    }

    private func detailHeader(_ entry: ScanHistoryEntry, diff: HistoryDiff) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.rootName)
                .font(.system(size: 19, weight: .semibold))
            Text(entry.rootPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(entry.date.formatted(date: .long, time: .shortened))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func deltaCard(_ diff: HistoryDiff) -> some View {
        HStack(spacing: 10) {
            deltaMetric(
                "Всего",
                delta: diff.totalDelta,
                before: diff.before.totalSize,
                after: diff.totalAfter
            )
            deltaMetric(
                "Файлов",
                delta: diff.fileCountDelta.map(Int64.init),
                before: Int64(diff.before.fileCount),
                after: diff.fileCountAfter.map(Int64.init),
                isCount: true
            )
        }
    }

    private func deltaMetric(
        _ title: String,
        delta: Int64?,
        before: Int64,
        after: Int64?,
        isCount: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(deltaText(delta, isCount: isCount))
                .font(.system(size: 19, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(deltaColor(delta))
            HStack(spacing: 4) {
                Text(isCount ? ByteFormat.count(Int(before)) : ByteFormat.string(before))
                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .bold))
                Text(after.map { isCount ? ByteFormat.count(Int($0)) : ByteFormat.string($0) } ?? "—")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10))
    }

    private func changesCard(_ diff: HistoryDiff) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Что изменилось")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("верхний уровень")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Rectangle().fill(Theme.border).frame(height: 1)

            if diff.comparableChanges.isEmpty {
                Text("Размеры верхнего уровня не изменились")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ForEach(diff.comparableChanges.prefix(12)) { change in
                    HStack(spacing: 8) {
                        Image(systemName: change.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(deltaColor(change.delta))
                            .frame(width: 14)
                        Text(change.path)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text("\(ByteFormat.string(change.before)) → \(ByteFormat.string(change.after))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(signedBytes(change.delta))
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(deltaColor(change.delta))
                            .frame(width: 78, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func unavailable(_ diff: HistoryDiff) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                diff.hasCurrent ? "Текущий скан другой папки" : "Нет текущего скана",
                systemImage: diff.hasCurrent ? "exclamationmark.triangle" : "info.circle"
            )
            .font(.system(size: 11.5, weight: .semibold))
            Text(
                diff.hasCurrent
                    ? "Чтобы сравнить размеры, просканируйте «\(diff.before.rootPath)» снова."
                    : "Просканируйте папку — и история покажет, что выросло с прошлого раза."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10))
    }

    private func actions(_ entry: ScanHistoryEntry) -> some View {
        HStack(spacing: 8) {
            AccentButton(title: "Сканировать снова", symbol: "arrow.clockwise") {
                model.rescanHistory(entry)
            }
            GhostButton(title: "Удалить запись", symbol: "trash", tint: Theme.danger) {
                model.deleteHistory(entry)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Хранятся последние 30 сканов, локально")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            if !model.scanHistory.isEmpty {
                Button("Очистить историю") { showClearConfirmation = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func signedBytes(_ value: Int64) -> String {
        guard value != 0 else { return L10n.isEnglish ? "no change" : "без изменений" }
        return (value > 0 ? "+" : "−") + ByteFormat.string(abs(value))
    }

    private func deltaText(_ delta: Int64?, isCount: Bool) -> String {
        guard let delta else { return "—" }
        guard delta != 0 else { return L10n.isEnglish ? "no change" : "без изменений" }
        let prefix = delta > 0 ? "+" : "−"
        let magnitude = isCount ? "\(abs(delta))" : ByteFormat.string(abs(delta))
        return prefix + magnitude
    }

    private func deltaColor(_ delta: Int64?) -> Color {
        guard let delta, delta != 0 else { return .secondary }
        return delta > 0 ? Theme.danger : .green
    }
}
