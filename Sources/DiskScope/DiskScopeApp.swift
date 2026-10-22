import AppKit
import DiskScopeKit
import SwiftUI

@main
struct DiskScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("DiskScope") {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .undoRedo) {
                Button("Отменить удаление") { model.undoLastTrash() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.canUndoTrash)
            }

            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Настройки…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .saveItem) {
                Menu("Экспортировать отчёт") {
                    Button("CSV — текущая папка") {
                        model.exportReport(format: .csv, scope: .currentFolder)
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("HTML — текущая папка") {
                        model.exportReport(format: .html, scope: .currentFolder)
                    }
                    Divider()
                    Button("CSV — весь скан") {
                        model.exportReport(format: .csv, scope: .wholeScan)
                    }
                    Button("HTML — весь скан") {
                        model.exportReport(format: .html, scope: .wholeScan)
                    }
                }
                .disabled(model.tree == nil)
            }

            CommandMenu("Диск") {
                Button("Сканировать домашнюю папку") { model.scanHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(model.isScanning)
                Button("Выбрать папку…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.isScanning)
                Divider()
                Button("Сканировать снова") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.tree == nil || model.isScanning)
                Button("Остановить сканирование") { model.cancelScan() }
                    .disabled(!model.isScanning)
            }

            CommandGroup(after: .sidebar) {
                Button("Палитра команд…") { model.showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Карта папки") { model.tab = .map }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Крупнейшие объекты") { model.tab = .largest }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Типы файлов") { model.tab = .types }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Медиа-поиск") { model.tab = .media }
                    .keyboardShortcut("4", modifiers: .command)
                    .disabled(model.tree == nil)
                Button("Очистка") { model.tab = .cleanup }
                    .keyboardShortcut("5", modifiers: .command)
                    .disabled(model.tree == nil)
                Divider()
                Button("Наверх") { model.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!model.canGoUp)
                Button("Показать в Finder") {
                    if model.selection.isEmpty {
                        model.revealCurrentFolder()
                    } else {
                        model.revealSelection()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.tree == nil)
                Button("Переместить в Корзину…") { model.requestTrashSelection() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(!model.canTrashSelection)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
