import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var targetGB: Double = 10
    @AppStorage(AppSettingsKeys.staleMonths) private var staleMonths = 12

    private var suggestions: [CleanupSuggestion] { model.cleanupSuggestions }
    private var staleItems: [CleanupSuggestion] { model.staleSuggestions }

    private var groups: [(risk: CleanupRisk, items: [CleanupSuggestion])] {
        CleanupRisk.allCases.compactMap { risk in
            let items = suggestions.filter { $0.risk == risk && $0.ruleID != "stale" }
            return items.isEmpty ? nil : (risk, items)
        }
    }

    private var targetBytes: Int64 {
        max(Int64(targetGB) * 1_000_000_000, 1)
    }

    private var targetFraction: Double {
        Double(model.cleanupSelectedSize) / Double(targetBytes)
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            Rectangle().fill(Theme.border).frame(height: 1)
            content
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardSurface()
        .task {
            model.loadCleanupSuggestionsIfNeeded()
        }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Можно освободить")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(model.cleanupLoading ? "…" : ByteFormat.string(model.cleanupTotalSize))
                    .font(AppFont.number(24))
                    .monospacedDigit()
                Text(
                    suggestions.isEmpty
                        ? "Проверяем известные кэши и старые файлы"
                        : "\(Plural.elements(suggestions.count)) по правилам очистки"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Цель")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(Int(targetGB)) ГБ")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                }
                Slider(value: $targetGB, in: 1...200, step: 1)
                    .frame(width: 190)
                    .tint(Theme.accent)
                HStack(spacing: 6) {
                    ProgressBar(fraction: targetFraction, height: 6)
                        .frame(width: 150)
                    Text(ByteFormat.percent(model.cleanupSelectedSize, of: targetBytes))
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("Выбрано")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(ByteFormat.string(model.cleanupSelectedSize))
                    .font(AppFont.number(18))
                    .monospacedDigit()
                Text(Plural.items(model.cleanupSelectedCount))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.cleanupLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Считаем рекомендации…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if suggestions.isEmpty {
            EmptyFolderView(
                symbol: "sparkles",
                title: "Нечего чистить",
                message: "В текущем скане не нашлось известных кэшей, старых установщиков или бэкапов. "
                    + "Это нормально: правила работают только с тем, что видно в дереве."
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !staleItems.isEmpty {
                        staleSection
                    }
                    ForEach(groups, id: \.risk) { group in
                        section(risk: group.risk, items: group.items)
                    }
                }
                .padding(14)
            }
        }
    }

    private var staleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text("Заброшенные файлы")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(model.staleResult.totalFiles)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.subtleFill, in: Capsule())
                Spacer()
                Text(ByteFormat.string(model.staleResult.totalBytes))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Picker("Месяцев", selection: $staleMonths) {
                    Text("6 мес.").tag(6)
                    Text("12 мес.").tag(12)
                    Text("24 мес.").tag(24)
                    Text("36 мес.").tag(36)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 92)
                .onChange(of: staleMonths) { _, newValue in
                    model.setStaleMonths(newValue)
                }
            }
            .padding(.horizontal, 4)

            Text("Файлы крупнее 10 МБ без изменений дольше выбранного срока. Системные пути, пакеты, .git, node_modules и библиотеки исключены.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            VStack(spacing: 1) {
                ForEach(staleItems.prefix(20)) { suggestion in
                    CleanupRow(
                        suggestion: suggestion,
                        isSelected: model.cleanupSelection.contains(suggestion.id),
                        onToggle: { model.toggleCleanupSelection(suggestion.id) },
                        onReveal: { model.reveal(indices: [suggestion.nodeIndex]) }
                    )
                }
            }
            .padding(3)
            .background(Theme.subtleFill.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )

            HStack(spacing: 8) {
                Button("Выбрать топ-20") {
                    model.selectCleanup(Array(staleItems.prefix(20)))
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent)
                if model.staleResult.truncated {
                    Text("Показаны 20 из \(model.staleResult.totalFiles)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func section(risk: CleanupRisk, items: [CleanupSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: risk.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(risk.tint)
                Text(risk.title)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.subtleFill, in: Capsule())
                Spacer()
                Text(ByteFormat.string(items.reduce(Int64(0)) { $0 + $1.size }))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if risk != .expert {
                    let selectable = items.filter { $0.disposition == .trash }
                    if !selectable.isEmpty {
                        Button(selectable.count == items.count ? "Выбрать все" : "Выбрать всё, кроме Корзины") {
                            model.selectCleanup(selectable)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(.horizontal, 4)

            Text(risk.explanation)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 1) {
                ForEach(items) { suggestion in
                    CleanupRow(
                        suggestion: suggestion,
                        isSelected: model.cleanupSelection.contains(suggestion.id),
                        onToggle: { model.toggleCleanupSelection(suggestion.id) },
                        onReveal: { model.reveal(indices: [suggestion.nodeIndex]) }
                    )
                }
            }
            .padding(3)
            .background(Theme.subtleFill.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Выбрано: \(Plural.items(model.cleanupSelectedCount)) · \(ByteFormat.string(model.cleanupSelectedSize))")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if model.cleanupHasPermanentSelection {
                Label("безвозвратно", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
            Spacer()
            GhostButton(title: "Снять выбор") {
                model.clearCleanupSelection()
            }
            AccentButton(title: "Очистить…", symbol: "sparkles") {
                model.requestCleanup()
            }
            .disabled(!model.cleanupCanApply)
            .opacity(model.cleanupCanApply ? 1 : 0.45)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct CleanupRow: View {
    let suggestion: CleanupSuggestion
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Снять выбор" : "Выбрать")

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.13))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: suggestion.risk.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(suggestion.name.isEmpty ? suggestion.title : suggestion.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if suggestion.disposition == .deletePermanently {
                        Text("безвозвратно")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Theme.danger.opacity(0.11), in: Capsule())
                    }
                }
                Text(suggestion.relativePath.isEmpty ? suggestion.path : suggestion.relativePath)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(suggestion.path)
                Text(suggestion.reason)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            Spacer(minLength: 8)

            Text(ByteFormat.string(suggestion.size))
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            IconActionButton(
                symbol: "magnifyingglass",
                help: "Показать в Finder",
                action: onReveal
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Theme.accent.opacity(0.055) : Color.clear)
        )
    }

    private var tint: Color {
        suggestion.disposition == .deletePermanently ? Theme.danger : suggestion.risk.tint
    }
}

private extension CleanupRisk {
    var tint: Color {
        switch self {
        case .safe: return Theme.success
        case .review: return Theme.warning
        case .expert: return Theme.danger
        }
    }
}
