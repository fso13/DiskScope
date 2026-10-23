import AppKit
import Foundation

extension AppModel {
    public func revealSearchHit(_ hit: SearchHit) {
        search.show = false
        browser.reveal(indices: [hit.index])
    }

    public func navigateToSearchHit(_ hit: SearchHit) {
        guard let tree, hit.index > 0, Int(hit.index) < tree.count else { return }
        search.show = false
        let node = tree.node(hit.index)
        if node.nodeKind.isContainer {
            navigate(to: hit.index)
        } else {
            if node.parent >= 0 {
                navigate(to: node.parent)
            }
            browser.reveal(indices: [hit.index])
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
        search.show = false
        selection = [hit.index]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.trashOperations.requestSelection()
        }
    }
}
