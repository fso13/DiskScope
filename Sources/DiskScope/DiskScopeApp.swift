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

            CommandMenu("Диск") {
                Button("Сканировать домашнюю папку") { model.scanHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Выбрать папку…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Сканировать снова") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.tree == nil)
                Button("Остановить сканирование") { model.cancelScan() }
                    .disabled(!model.isScanning)
            }

            CommandGroup(after: .sidebar) {
                Button("Карта папки") { model.tab = .map }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Крупнейшие объекты") { model.tab = .largest }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Типы файлов") { model.tab = .types }
                    .keyboardShortcut("3", modifiers: .command)
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
