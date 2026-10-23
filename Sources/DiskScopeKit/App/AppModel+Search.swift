import AppKit
import Foundation

extension AppModel {
    // MARK: - Global search

    /// Builds the name index on demand. Results are applied only for the current tree.
    public func ensureSearchIndex() {
        guard let tree else {
            resetSearch()
            return
        }
        if let index = searchIndex, index.treeIdentifier == ObjectIdentifier(tree) {
            searchReady = true
            return
        }
        guard !searchIndexing else { return }

        searchIndexGeneration += 1
        let generation = searchIndexGeneration
        searchIndexing = true
        searchReady = false
        let treeToIndex = tree

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let index = ScanSearchIndex(tree: treeToIndex)
            DispatchQueue.main.async {
                guard let self,
                      self.searchIndexGeneration == generation,
                      self.tree === treeToIndex else { return }
                self.searchIndex = index
                self.searchIndexing = false
                self.searchReady = true
                self.runSearch()
            }
        }
    }

    func scheduleSearch() {
        searchWorkItem?.cancel()
        guard showGlobalSearch else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.runSearch()
        }
        searchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    func runSearch() {
        guard showGlobalSearch, let tree else { return }
        guard let index = searchIndex, index.treeIdentifier == ObjectIdentifier(tree) else {
            ensureSearchIndex()
            return
        }

        let query = SearchQuery(
            text: globalSearchText,
            minimumSize: searchMinimumSize,
            category: searchCategory,
            kind: searchKind,
            dateRange: searchDateRange,
            sort: searchSort,
            limit: 500
        )
        searchQueryGeneration += 1
        let generation = searchQueryGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = index.search(query)
            DispatchQueue.main.async {
                guard let self,
                      self.searchQueryGeneration == generation,
                      self.showGlobalSearch else { return }
                self.searchHits = results.hits
                self.searchTotal = results.total
            }
        }
    }

    func resetSearch() {
        searchIndexGeneration += 1
        searchQueryGeneration += 1
        searchWorkItem?.cancel()
        searchIndex = nil
        searchHits = []
        searchTotal = 0
        searchIndexing = false
        searchReady = false
        showGlobalSearch = false
        globalSearchText = ""
    }

    public func revealSearchHit(_ hit: SearchHit) {
        showGlobalSearch = false
        reveal(indices: [hit.index])
    }

    public func navigateToSearchHit(_ hit: SearchHit) {
        guard let tree, hit.index > 0, Int(hit.index) < tree.count else { return }
        showGlobalSearch = false
        let node = tree.node(hit.index)
        if node.nodeKind.isContainer {
            navigate(to: hit.index)
        } else {
            if node.parent >= 0 {
                navigate(to: node.parent)
            }
            reveal(indices: [hit.index])
        }
    }

    public func addSearchHitToCollection(_ hit: SearchHit) {
        addToCollection([hit.index])
        showToast("В коллекции: \(collectionSummary)", symbol: "tray.full")
    }

    public func requestTrashSearchHit(_ hit: SearchHit) {
        guard let tree, hit.index > 0, Int(hit.index) < tree.count, !tree.isDeleted(hit.index) else {
            return
        }
        showGlobalSearch = false
        selection = [hit.index]
        // Let the search sheet finish dismissing before showing the confirmation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.requestTrashSelection()
        }
    }
}
