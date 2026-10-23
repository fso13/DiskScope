import Combine
import Foundation

/// Owns global-search state and the asynchronous name index.
@MainActor
public final class SearchModel: ObservableObject {
    @Published public var show = false {
        didSet {
            if show {
                ensureIndex()
                schedule()
            }
        }
    }
    @Published public var text = "" { didSet { schedule() } }
    @Published public var minimumSize: Int64 = 0 { didSet { schedule() } }
    @Published public var category: FileCategory? { didSet { schedule() } }
    @Published public var kind: SearchKind = .any { didSet { schedule() } }
    @Published public var dateRange: SearchDateRange = .any { didSet { schedule() } }
    @Published public var sort: SearchSort = .size { didSet { schedule() } }
    @Published public internal(set) var hits: [SearchHit] = []
    @Published public internal(set) var total = 0
    @Published public internal(set) var indexing = false
    @Published public internal(set) var ready = false

    private var treeProvider: () -> ScanTree? = { nil }
    private var index: ScanSearchIndex?
    private var indexGeneration = 0
    private var queryGeneration = 0
    private var workItem: DispatchWorkItem?

    public init() {}

    func attach(treeProvider: @escaping () -> ScanTree?) {
        self.treeProvider = treeProvider
    }

    public func ensureIndex() {
        guard let tree = treeProvider() else {
            reset()
            return
        }
        if let index, index.treeIdentifier == ObjectIdentifier(tree) {
            ready = true
            return
        }
        guard !indexing else { return }

        indexGeneration += 1
        let generation = indexGeneration
        indexing = true
        ready = false
        let treeToIndex = tree

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let built = ScanSearchIndex(tree: treeToIndex)
            DispatchQueue.main.async {
                guard let self,
                      self.indexGeneration == generation,
                      self.treeProvider() === treeToIndex else { return }
                self.index = built
                self.indexing = false
                self.ready = true
                self.run()
            }
        }
    }

    func schedule() {
        workItem?.cancel()
        guard show else { return }
        let item = DispatchWorkItem { [weak self] in self?.run() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    func run() {
        guard show, let tree = treeProvider() else { return }
        guard let index, index.treeIdentifier == ObjectIdentifier(tree) else {
            ensureIndex()
            return
        }
        let query = SearchQuery(
            text: text,
            minimumSize: minimumSize,
            category: category,
            kind: kind,
            dateRange: dateRange,
            sort: sort,
            limit: 500
        )
        queryGeneration += 1
        let generation = queryGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = index.search(query)
            DispatchQueue.main.async {
                guard let self,
                      self.queryGeneration == generation,
                      self.show else { return }
                self.hits = results.hits
                self.total = results.total
            }
        }
    }

    public func reset() {
        indexGeneration += 1
        queryGeneration += 1
        workItem?.cancel()
        index = nil
        hits = []
        total = 0
        indexing = false
        ready = false
        show = false
        text = ""
        minimumSize = 0
        category = nil
        kind = .any
        dateRange = .any
        sort = .size
    }
}
