import AppKit
import DiskScopeKit
import SwiftUI

@main
struct DiskScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    private let sparkle = SparkleUpdater()

    var body: some Scene {
        WindowGroup("DiskScope") {
            ContentView()
                .environmentObject(model)
                .onAppear { appDelegate.model = model }
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

            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") {
                    sparkle.checkForUpdates()
                }
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
                        model.report.exportReport(format: .csv, scope: .currentFolder)
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("HTML — текущая папка") {
                        model.report.exportReport(format: .html, scope: .currentFolder)
                    }
                    Divider()
                    Button("CSV — весь скан") {
                        model.report.exportReport(format: .csv, scope: .wholeScan)
                    }
                    Button("HTML — весь скан") {
                        model.report.exportReport(format: .html, scope: .wholeScan)
                    }
                }
                .disabled(!model.report.canExportReport)
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
                Button("Найти по скану…") { model.search.show = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(model.tree == nil)
                Button("Инспектор") { model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(model.tree == nil)
                Button("Быстрый просмотр") { model.inspector.previewSelection() }
                    .keyboardShortcut("y", modifiers: .command)
                    .disabled(!model.inspector.canQuickLook)
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
                Button("Коллекция") { model.showCollection = true }
                    .keyboardShortcut("6", modifiers: .command)
                    .disabled(model.collection.isEmpty)
                Button("Диск") { model.showDiskOverview() }
                    .keyboardShortcut("7", modifiers: .command)
                    .disabled(model.tree == nil)
                Button("История сканов…") { model.history.show = true }
                    .keyboardShortcut("8", modifiers: .command)
                Button("Дубликаты") { model.tab = .duplicates }
                    .keyboardShortcut("9", modifiers: .command)
                    .disabled(model.tree == nil)
                Button("Похожие изображения") { model.tab = .similar }
                    .keyboardShortcut("0", modifiers: .command)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel? {
        didSet {
            menuBarController?.model = model
            if let pendingScanPath, let model {
                model.scan(path: pendingScanPath)
                self.pendingScanPath = nil
            }
        }
    }

    private var pendingScanPath: String?
    private var menuBarController: MenuBarController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: AppSettingsKeys.menuBarMonitor)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarSettingsChanged),
            name: .menuBarSettingsChanged,
            object: nil
        )
        configureMenuBar()
    }

    @objc private func menuBarSettingsChanged() {
        configureMenuBar()
        menuBarController?.update()
    }

    private func configureMenuBar() {
        let enabled = UserDefaults.standard.bool(forKey: AppSettingsKeys.menuBarMonitor)
        if enabled {
            if menuBarController == nil {
                menuBarController = MenuBarController(model: model) { [weak self] in
                    self?.showMainWindow()
                }
                menuBarController?.start()
            }
        } else {
            menuBarController?.stop()
            menuBarController = nil
        }
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }

    @objc func scanFolder(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              let folder = urls.first(where: { url in
                  var isDirectory: ObjCBool = false
                  return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                      && isDirectory.boolValue
              }) else {
            error.pointee = "Choose a folder to scan." as NSString
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if let model {
            model.scan(path: folder.path)
        } else {
            pendingScanPath = folder.path
        }
    }
}
