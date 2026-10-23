import AppKit
import Foundation

extension AppModel {
    public func chooseFolder() {
        guard !isScanning else { return }
        let panel = NSOpenPanel()
        panel.title = "Выберите папку для анализа"
        panel.message = "DiskScope посчитает, что занимает место внутри выбранной папки."
        panel.prompt = "Сканировать"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url {
            scan(path: url.path)
        }
    }

    public func scanHome() {
        scan(path: homePath)
    }

    public func scanVolume(_ volume: VolumeInfo) {
        scan(path: volume.path)
    }
}
