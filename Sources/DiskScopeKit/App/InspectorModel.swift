import AppKit
import Combine
import Foundation

/// File-system metadata shown in the inspector for a single node.
public struct FileMetadata: Equatable, Sendable {
    public let logicalSize: Int64?
    public let created: Date?
    public let modified: Date?
    public let isPackage: Bool

    public init(logicalSize: Int64?, created: Date?, modified: Date?, isPackage: Bool) {
        self.logicalSize = logicalSize
        self.created = created
        self.modified = modified
        self.isPackage = isPackage
    }
}

/// Owns the inspector target, Quick Look, node metadata and file actions.
@MainActor
public final class InspectorModel: ObservableObject {
    @Published public var quickLookURL: URL?
    @Published public private(set) var metadata: FileMetadata?
    @Published public private(set) var metadataIndex: Int32?

    private var treeProvider: () -> ScanTree? = { nil }
    private var currentIndexProvider: () -> Int32 = { 0 }
    private var selectionProvider: () -> Set<Int32> = { [] }
    private var toastHandler: (String, String) -> Void = { _, _ in }
    private var errorHandler: (String) -> Void = { _ in }
    private var metadataTreeID: ObjectIdentifier?

    public init() {}

    func attach(
        treeProvider: @escaping () -> ScanTree?,
        currentIndexProvider: @escaping () -> Int32,
        selectionProvider: @escaping () -> Set<Int32>,
        toast: @escaping (String, String) -> Void,
        error: @escaping (String) -> Void
    ) {
        self.treeProvider = treeProvider
        self.currentIndexProvider = currentIndexProvider
        self.selectionProvider = selectionProvider
        self.toastHandler = toast
        self.errorHandler = error
    }

    // MARK: - Inspector target

    public var inspectorNode: Int32? {
        let selection = selectionProvider()
        if selection.count == 1 { return selection.first }
        if selection.isEmpty { return currentIndexProvider() }
        return nil
    }

    public var canQuickLook: Bool {
        guard let tree = treeProvider() else { return false }
        return selectionProvider().contains { index in
            index > 0 && Int(index) < tree.count
                && !tree.isDeleted(index)
                && tree.node(index).nodeKind == .file
        }
    }

    // MARK: - Quick Look

    public func previewSelection() {
        guard let tree = treeProvider() else { return }
        let index = selectionProvider().sorted().first { candidate in
            candidate > 0 && Int(candidate) < tree.count
                && !tree.isDeleted(candidate)
                && tree.node(candidate).nodeKind == .file
        }
        guard let index else {
            quickLookURL = nil
            return
        }
        previewNode(index)
    }

    public func previewNode(_ index: Int32) {
        guard let tree = treeProvider(), index > 0, Int(index) < tree.count,
              !tree.isDeleted(index),
              tree.node(index).nodeKind == .file else { return }
        quickLookURL = tree.url(of: index)
    }

    // MARK: - Metadata

    /// Returns metadata only when it belongs to the current tree and node.
    public func metadata(for index: Int32) -> FileMetadata? {
        guard metadataIndex == index,
              let tree = treeProvider(),
              metadataTreeID == ObjectIdentifier(tree) else { return nil }
        return metadata
    }

    public func loadMetadata(for index: Int32) {
        guard let tree = treeProvider(), index > 0, Int(index) < tree.count else {
            resetMetadata()
            return
        }
        let node = tree.node(index)
        guard node.nodeKind != .aggregate else {
            resetMetadata()
            return
        }
        let treeID = ObjectIdentifier(tree)
        let url = tree.url(of: index)
        metadata = nil
        metadataIndex = index
        metadataTreeID = treeID

        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isPackageKey,
        ])
        guard metadataIndex == index, metadataTreeID == treeID else { return }
        metadata = FileMetadata(
            logicalSize: values?.fileSize.map(Int64.init),
            created: values?.creationDate,
            modified: values?.contentModificationDate,
            isPackage: values?.isPackage ?? false
        )
    }

    private func resetMetadata() {
        metadata = nil
        metadataIndex = nil
        metadataTreeID = nil
    }

    // MARK: - File actions

    public func copyPaths(_ indices: [Int32]) {
        guard let tree = treeProvider() else { return }
        let paths = indices.compactMap { index -> String? in
            guard index >= 0, Int(index) < tree.count, !tree.isDeleted(index) else { return nil }
            return tree.path(of: index)
        }
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        toastHandler(
            paths.count == 1 ? "Путь скопирован" : "Скопировано путей: \(paths.count)",
            "doc.on.doc"
        )
    }

    public func openInTerminal(_ index: Int32) {
        guard let tree = treeProvider(), index >= 0, Int(index) < tree.count,
              !tree.isDeleted(index) else { return }
        let url = tree.url(of: index)
        let folder = tree.isDirectory(index) ? url : url.deletingLastPathComponent()
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        guard FileManager.default.fileExists(atPath: terminal.path) else {
            errorHandler("Не удалось найти Terminal.app")
            return
        }
        NSWorkspace.shared.open(
            [folder],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.errorHandler("Не удалось открыть терминал: \(error.localizedDescription)")
            }
        }
    }
}
