import AppKit
import DiskScopeKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var timer: Timer?
    weak var model: AppModel?
    private let showApp: () -> Void

    init(model: AppModel?, showApp: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.model = model
        self.showApp = showApp
        super.init()
    }

    func start() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "internaldrive",
            accessibilityDescription: "DiskScope"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.menu = makeMenu()
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func update() {
        let volumes = VolumeInfo.loadAll()
        let volume = volumes.first(where: { $0.path == "/" }) ?? volumes.first
        guard let volume else {
            statusItem.button?.title = "—"
            return
        }
        let status = MenuBarStatus(volume: volume)
        let rawMode = UserDefaults.standard.string(forKey: "app.settings.menuBarDisplay")
        let mode = MenuBarDisplayMode(rawValue: rawMode ?? "") ?? .free
        statusItem.button?.title = status.title(mode)
        statusItem.button?.setAccessibilityLabel(status.accessibilityLabel(mode))
        statusItem.menu = makeMenu(status: status)
    }

    func menuWillOpen(_ menu: NSMenu) {
        update()
    }

    private func makeMenu(status: MenuBarStatus? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        if let status {
            let free = NSMenuItem(
                title: text(
                    "Свободно: \(ByteFormat.string(status.freeBytes)) из \(ByteFormat.string(status.totalBytes))",
                    "Free: \(ByteFormat.string(status.freeBytes)) of \(ByteFormat.string(status.totalBytes))"
                ),
                action: nil,
                keyEquivalent: ""
            )
            free.isEnabled = false
            menu.addItem(free)

            let used = NSMenuItem(
                title: text(
                    "Использовано: \(ByteFormat.string(status.usedBytes)) (\(ByteFormat.percent(status.usedBytes, of: status.totalBytes)))",
                    "Used: \(ByteFormat.string(status.usedBytes)) (\(ByteFormat.percent(status.usedBytes, of: status.totalBytes)))"
                ),
                action: nil,
                keyEquivalent: ""
            )
            used.isEnabled = false
            menu.addItem(used)

            if status.purgeableBytes > 0 {
                let purgeable = NSMenuItem(
                    title: text(
                        "Purgeable: \(ByteFormat.string(status.purgeableBytes))",
                        "Purgeable: \(ByteFormat.string(status.purgeableBytes))"
                    ),
                    action: nil,
                    keyEquivalent: ""
                )
                purgeable.isEnabled = false
                menu.addItem(purgeable)
            }
            menu.addItem(.separator())
        }

        add("Открыть DiskScope", "Open DiskScope", #selector(openAppAction), to: menu)
        add("Сканировать домашнюю папку", "Scan Home folder", #selector(scanHomeAction), to: menu)
        add("Обновить", "Refresh", #selector(refreshAction), to: menu)
        menu.addItem(.separator())
        add("Настройки…", "Settings…", #selector(settingsAction), to: menu)
        add("Выйти", "Quit", #selector(quitAction), to: menu)
        return menu
    }

    private func add(_ ru: String, _ en: String, _ action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: text(ru, en), action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func text(_ ru: String, _ en: String) -> String {
        L10n.isEnglish ? en : ru
    }

    @objc private func openAppAction() {
        showApp()
    }

    @objc private func scanHomeAction() {
        model?.scanHome()
        showApp()
    }

    @objc private func refreshAction() {
        update()
    }

    @objc private func settingsAction() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
