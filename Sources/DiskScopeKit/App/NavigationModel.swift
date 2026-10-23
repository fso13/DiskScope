import Combine
import Foundation

/// Owns the current folder, selection and the visible table rows.
@MainActor
public final class NavigationModel: ObservableObject {
    @Published public internal(set) var currentIndex: Int32 = 0
    @Published public internal(set) var selection: Set<Int32> = []
    @Published public internal(set) var rows: [AppModel.ItemRow] = []
    @Published public internal(set) var rowsTotal = 0
    @Published public internal(set) var rowsTruncated = false
    @Published public var searchText = "" { didSet { rebuild() } }
    @Published public var sortOrder: [KeyPathComparator<AppModel.ItemRow>] = [
        KeyPathComparator(\.size, order: .reverse),
    ] {
        didSet { rebuild() }
    }
    @Published public var categoryFilter: FileCategory?

    private var treeProvider: () -> ScanTree? = { nil }
    private let rowLimit = 2500

    public init() {}

    func attach(treeProvider: @escaping () -> ScanTree?) {
        self.treeProvider = treeProvider
    }

    func navigate(to index: Int32) {
        guard let tree = treeProvider(),
              index >= 0, Int(index) < tree.count,
              tree.node(index).nodeKind.isContainer else { return }
        currentIndex = index
        selection = []
        searchText = ""
        rebuild()
    }

    func goUp() {
        guard let tree = treeProvider() else { return }
        let parent = tree.node(currentIndex).parent
        if parent >= 0 { navigate(to: parent) }
    }

    func reset() {
        currentIndex = 0
        selection = []
        rows = []
        rowsTotal = 0
        rowsTruncated = false
    }

    func adjustToSurvivingAncestor(in tree: ScanTree) {
        guard tree.isDeleted(currentIndex) else { return }
        var cursor = currentIndex
        while cursor > 0, tree.isDeleted(cursor) {
            cursor = tree.node(cursor).parent
        }
        currentIndex = max(cursor, 0)
        selection = []
        rebuild()
    }

    public func rebuild() {
        guard let tree = treeProvider(), Int(currentIndex) < tree.count else {
            rows = []
            rowsTotal = 0
            rowsTruncated = false
            return
        }
        let parentSize = max(tree.node(currentIndex).size, 1)
        var indices = tree.children(of: currentIndex)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            indices = indices.filter {
                tree.name(of: $0).localizedCaseInsensitiveContains(query)
            }
        }
        var result: [AppModel.ItemRow] = []
        result.reserveCapacity(min(indices.count, rowLimit))
        for index in indices {
            result.append(ItemRowFactory.make(
                tree: tree,
                index: index,
                parentSize: parentSize,
                includePaths: false
            ))
        }
        result.sort(using: sortOrder)
        rowsTotal = result.count
        rowsTruncated = result.count > rowLimit
        if result.count > rowLimit { result = Array(result.prefix(rowLimit)) }
        rows = result
    }

    func showFiles(of category: FileCategory) {
        categoryFilter = category
        searchText = ""
    }

    func clearCategoryFilter() {
        categoryFilter = nil
    }
}
