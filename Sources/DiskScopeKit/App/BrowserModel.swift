import AppKit
import Combine
import Foundation

/// Owns browser presentation (folder path, selection summary) and file actions.
@MainActor
public final class BrowserModel: ObservableObject {
    weak var appModel: AppModel?

    public init() {}

    func attach(appModel: AppModel) {
        self.appModel = appModel
    }

    // MARK: - Presentation

    public var currentName: String {
        guard let model = appModel, let tree = model.tree else { return "" }
        if model.currentIndex == 0 { return rootDisplayName }
        let name = tree.name(of: model.currentIndex)
        return name.isEmpty ? rootDisplayName : name
    }

    public var breadcrumbs: [Int32] {
        guard let model = appModel, let tree = model.tree else { return [] }
        var chain: [Int32] = []
        var cursor = model.currentIndex
        while cursor >= 0, chain.count < 256 {
            chain.append(cursor)
            let parent = tree.node(cursor).parent
            if parent < 0 { break }
            cursor = parent
        }
        return chain.reversed()
    }

    public var canGoUp: Bool {
        guard let model = appModel, let tree = model.tree else { return false }
        return tree.node(model.currentIndex).parent >= 0
    }

    public var currentSize: Int64 {
        appModel?.tree?.node(appModel?.currentIndex ?? 0).size ?? 0
    }

    public var currentItemCount: Int {
        Int(appModel?.tree?.node(appModel?.currentIndex ?? 0).itemCount ?? 0)
    }

    public var currentDirectCount: Int {
        guard let model = appModel, let tree = model.tree, Int(model.currentIndex) < tree.count else {
            return 0
        }
        return Int(tree.node(model.currentIndex).childrenCount)
    }

    public var currentPath: String {
        guard let model = appModel else { return "" }
        return model.tree?.path(of: model.currentIndex) ?? ""
    }

    public var selectedSize: Int64 {
        guard let model = appModel, let tree = model.tree else { return 0 }
        return model.selection.reduce(Int64(0)) { $0 + tree.node($1).size }
    }

    public var selectedCount: Int { appModel?.selection.count ?? 0 }

    public var canRevealSelection: Bool {
        guard let model = appModel, let tree = model.tree, !model.selection.isEmpty else {
            return false
        }
        return model.selection.contains { !tree.isDeleted($0) }
    }

    public var hasPermissionIssues: Bool {
        (appModel?.tree?.report.skippedItems ?? 0) > 0
    }

    public var volume: VolumeInfo? {
        guard let volumes = appModel?.volumes else { return nil }
        return volumes.first(where: { $0.isInternal }) ?? volumes.first
    }

    public var internalVolume: VolumeInfo? {
        guard let volumes = appModel?.volumes else { return nil }
        return volumes.first(where: { $0.path == "/" }) ?? volumes.first
    }

    public var currentNode: ScanNode? {
        guard let model = appModel, let tree = model.tree,
              model.currentIndex >= 0, Int(model.currentIndex) < tree.count else { return nil }
        return tree.node(model.currentIndex)
    }

    public var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    public var rootDisplayName: String {
        guard let model = appModel, let tree = model.tree else { return "DiskScope" }
        if tree.rootPath == "/" { return internalVolume?.name ?? "Macintosh HD" }
        let known: [String: String] = [
            homePath: "Домашняя папка",
            homePath + "/Applications": "Программы",
            "/Applications": "Программы",
            homePath + "/Downloads": "Загрузки",
            homePath + "/Documents": "Документы",
            homePath + "/Desktop": "Рабочий стол",
            homePath + "/Library": "Библиотека",
            homePath + "/Movies": "Видео",
            homePath + "/Music": "Музыка",
            homePath + "/Pictures": "Изображения",
        ]
        if let known = known[tree.rootPath] { return known }
        let name = URL(fileURLWithPath: tree.rootPath).lastPathComponent
        return name.isEmpty ? tree.rootPath : name
    }

    public var freeSpaceText: String {
        guard let volume = internalVolume else { return "—" }
        return ByteFormat.string(volume.freeBytes)
    }

    public func refreshVolumes() {
        appModel?.volumes = VolumeInfo.loadAll()
    }

    // MARK: - File actions

    public func activateRow(_ index: Int32) {
        guard let model = appModel, let tree = model.tree,
              index >= 0, Int(index) < tree.count else { return }
        guard tree.node(index).nodeKind != .aggregate else { return }
        if tree.node(index).nodeKind == .directory {
            model.navigate(to: index)
        } else {
            reveal(indices: [index])
        }
    }

    public func openRow(_ index: Int32) {
        guard let model = appModel, let tree = model.tree,
              index >= 0, Int(index) < tree.count else { return }
        let node = tree.node(index)
        guard node.nodeKind != .aggregate else { return }
        if node.nodeKind.isContainer {
            model.navigate(to: index)
        } else {
            let url = tree.url(of: index)
            if !NSWorkspace.shared.open(url) {
                model.errorMessage = "Не удалось открыть «\(tree.name(of: index))»"
            }
        }
    }

    public func reveal(indices: [Int32]) {
        guard let tree = appModel?.tree else { return }
        let urls = indices.compactMap { index -> URL? in
            guard index >= 0, Int(index) < tree.count, !tree.isDeleted(index) else { return nil }
            return tree.url(of: index)
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    public func revealSelection() {
        reveal(indices: Array(appModel?.selection ?? []))
    }

    public func revealCurrentFolder() {
        guard let model = appModel, let tree = model.tree else { return }
        NSWorkspace.shared.activateFileViewerSelecting([tree.url(of: model.currentIndex)])
    }

    public func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}
