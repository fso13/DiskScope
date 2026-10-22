import AppKit
import SwiftUI

/// Custom full-width window chrome: native traffic lights, brand, command
/// palette entry point and a compact status. The window itself has a hidden
/// title bar, so this row visually replaces it.
struct WindowTitleBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 0) {
            leftBar
                .frame(width: Theme.sidebarWidth)
            rightBar
        }
        .frame(height: Theme.titleBarHeight)
        .background {
            ZStack {
                HStack(spacing: 0) {
                    leftBackground
                        .frame(width: Theme.sidebarWidth)
                    Color.clear
                }
                WindowDragArea()
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.045))
                .frame(height: 1)
        }
        .sheet(isPresented: $model.showCommandPalette) {
            CommandPaletteView()
                .environmentObject(model)
        }
    }

    private var leftBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
                .frame(width: 76)

            AppMark(size: 22)
                .shadow(color: Theme.accent.opacity(0.45), radius: 7, y: 2)

            VStack(alignment: .leading, spacing: 0.5) {
                Text("DiskScope")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text("АНАЛИЗ ДИСКА")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.34))
            }
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.trailing, 10)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
    }

    private var rightBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 12)

            CommandCenterButton {
                model.showCommandPalette = true
            }

            Spacer(minLength: 12)

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Настройки (⌘,)")

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Text(statusText)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.subtleFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            .help("Данные не покидают Mac")
        }
        .padding(.horizontal, 14)
    }

    private var leftBackground: some View {
        ZStack {
            Theme.sidebarTop
            RadialGradient(
                colors: [Theme.accent.opacity(0.12), Color.clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 300
            )
        }
    }

    private var statusText: String {
        switch model.phase {
        case .scanning: return "Сканируем…"
        case .failed: return "Ошибка"
        default: return "Локально"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .scanning: return Theme.warning
        case .failed: return Theme.danger
        default: return Theme.success
        }
    }
}

private struct CommandCenterButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Команда или переход…")
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("⌘K")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 330)
            .background(Theme.subtleFill, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    hovering ? Theme.accent.opacity(0.4) : Theme.border,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Палитра команд (⌘K)")
    }
}

/// Lets the custom title bar move the window and zoom on double-click without
/// making the whole content draggable.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

// MARK: - Command palette

struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            divider
            commandList
            divider
            footer
        }
        .frame(width: 620, height: 440)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                searchFocused = true
            }
        }
        .onExitCommand {
            model.showCommandPalette = false
        }
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Команда или переход…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onSubmit {
                    execute(filteredCommands.first)
                }

            Text("esc")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var commandList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if filteredCommands.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Ничего не найдено")
                        .font(.system(size: 12, weight: .medium))
                    Text("Попробуйте другое слово.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(filteredCommands) { command in
                        PaletteRow(command: command) {
                            execute(command)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("\(filteredCommands.count) команд")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
            Text("↵ — выполнить")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text("esc — закрыть")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }

    private var filteredCommands: [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var commands: [PaletteCommand] {
        var items: [PaletteCommand] = []

        if model.isScanning {
            items.append(
                PaletteCommand(
                    id: "cancel-scan",
                    title: "Остановить сканирование",
                    subtitle: "Диск",
                    symbol: "xmark.circle",
                    shortcut: nil
                ) {
                    model.cancelScan()
                }
            )
        } else {
            items.append(contentsOf: [
                PaletteCommand(
                    id: "scan-home",
                    title: "Сканировать домашнюю папку",
                    subtitle: "Диск",
                    symbol: "house.fill",
                    shortcut: "⇧⌘H"
                ) {
                    model.scanHome()
                },
                PaletteCommand(
                    id: "choose-folder",
                    title: "Выбрать папку…",
                    subtitle: "Диск",
                    symbol: "folder.badge.plus",
                    shortcut: "⌘O"
                ) {
                    model.chooseFolder()
                },
            ])
            if model.tree != nil {
                items.append(
                    PaletteCommand(
                        id: "rescan",
                        title: "Сканировать снова",
                        subtitle: "Диск",
                        symbol: "arrow.clockwise",
                        shortcut: "⌘R"
                    ) {
                        model.rescan()
                    }
                )
            }
        }

        items.append(contentsOf: [
            PaletteCommand(
                id: "map",
                title: "Карта папки",
                subtitle: "Переход",
                symbol: "square.grid.2x2",
                shortcut: "⌘1"
            ) {
                model.tab = .map
            },
            PaletteCommand(
                id: "largest",
                title: "Крупнейшие объекты",
                subtitle: "Переход",
                symbol: "list.number",
                shortcut: "⌘2"
            ) {
                model.tab = .largest
            },
            PaletteCommand(
                id: "types",
                title: "Типы файлов",
                subtitle: "Переход",
                symbol: "chart.bar.xaxis",
                shortcut: "⌘3"
            ) {
                model.tab = .types
            },
        ])

        if model.tree != nil {
            items.append(
                PaletteCommand(
                    id: "media",
                    title: "Медиа-поиск",
                    subtitle: "Переход",
                    symbol: "photo.on.rectangle.angled",
                    shortcut: "⌘4"
                ) {
                    model.tab = .media
                }
            )
            items.append(
                PaletteCommand(
                    id: "cleanup",
                    title: "Очистка",
                    subtitle: "Переход",
                    symbol: "sparkles",
                    shortcut: "⌘5"
                ) {
                    model.tab = .cleanup
                }
            )
            items.append(
                PaletteCommand(
                    id: "disk",
                    title: "Полная картина диска",
                    subtitle: "Диск",
                    symbol: "internaldrive",
                    shortcut: "⌘7"
                ) {
                    model.showDiskOverview()
                }
            )
            items.append(
                PaletteCommand(
                    id: "history",
                    title: "История сканов…",
                    subtitle: "Диск",
                    symbol: "clock.arrow.circlepath",
                    shortcut: "⌘8"
                ) {
                    model.showHistory = true
                }
            )
            if model.collectionCount > 0 {
                items.append(
                    PaletteCommand(
                        id: "collection",
                        title: "Коллекция",
                        subtitle: "Файлы",
                        symbol: "tray.full",
                        shortcut: "⌘6"
                    ) {
                        model.showCollection = true
                    }
                )
            }
            items.append(
                PaletteCommand(
                    id: "search",
                    title: "Найти по скану…",
                    subtitle: "Поиск",
                    symbol: "magnifyingglass",
                    shortcut: "⌘F"
                ) {
                    model.showGlobalSearch = true
                }
            )
            items.append(
                PaletteCommand(
                    id: "inspector",
                    title: model.showInspector ? "Скрыть инспектор" : "Показать инспектор",
                    subtitle: "Вид",
                    symbol: "sidebar.right",
                    shortcut: "⌥⌘I"
                ) {
                    model.showInspector.toggle()
                }
            )
            if model.canQuickLook {
                items.append(
                    PaletteCommand(
                        id: "quick-look",
                        title: "Быстрый просмотр",
                        subtitle: "Файлы",
                        symbol: "eye",
                        shortcut: "⌘Y"
                    ) {
                        model.previewSelection()
                    }
                )
            }
            items.append(
                PaletteCommand(
                    id: "export-csv",
                    title: "Экспортировать отчёт: CSV",
                    subtitle: "Файл",
                    symbol: "square.and.arrow.up",
                    shortcut: "⇧⌘E"
                ) {
                    model.exportReport(format: .csv, scope: .currentFolder)
                }
            )
            items.append(
                PaletteCommand(
                    id: "export-html",
                    title: "Экспортировать отчёт: HTML",
                    subtitle: "Файл",
                    symbol: "square.and.arrow.up",
                    shortcut: nil
                ) {
                    model.exportReport(format: .html, scope: .currentFolder)
                }
            )
            items.append(
                PaletteCommand(
                    id: "reveal",
                    title: "Показать в Finder",
                    subtitle: "Файлы",
                    symbol: "folder",
                    shortcut: "⇧⌘R"
                ) {
                    if model.selection.isEmpty {
                        model.revealCurrentFolder()
                    } else {
                        model.revealSelection()
                    }
                }
            )
        }

        if model.canTrashSelection {
            items.append(
                PaletteCommand(
                    id: "trash",
                    title: "Переместить в Корзину…",
                    subtitle: "Файлы",
                    symbol: "trash",
                    shortcut: "⌘⌫"
                ) {
                    model.requestTrashSelection()
                }
            )
        }

        if model.canUndoTrash {
            items.append(
                PaletteCommand(
                    id: "undo-trash",
                    title: "Отменить удаление",
                    subtitle: "Файлы",
                    symbol: "arrow.uturn.backward",
                    shortcut: "⌘Z"
                ) {
                    model.undoLastTrash()
                }
            )
        }

        items.append(contentsOf: [
            PaletteCommand(
                id: "settings",
                title: "Настройки…",
                subtitle: "Приложение",
                symbol: "gearshape",
                shortcut: "⌘,"
            ) {
                openSettings()
            },
            PaletteCommand(
                id: "permissions",
                title: "Полный доступ к диску…",
                subtitle: "Система",
                symbol: "lock.shield",
                shortcut: nil
            ) {
                model.openFullDiskAccessSettings()
            },
            PaletteCommand(
                id: "about",
                title: "О программе DiskScope",
                subtitle: "Приложение",
                symbol: "info.circle",
                shortcut: nil
            ) {
                NSApp.orderFrontStandardAboutPanel(nil)
            },
        ])

        return items
    }

    private func execute(_ command: PaletteCommand?) {
        guard let command else { return }
        model.showCommandPalette = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            command.action()
        }
    }
}

private struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let shortcut: String?
    let action: () -> Void
}

private struct PaletteRow: View {
    let command: PaletteCommand
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.subtleFill)
                    Image(systemName: command.symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(command.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                hovering ? Theme.subtleFill : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
