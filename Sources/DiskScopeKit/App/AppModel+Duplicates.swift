import Foundation

extension AppModel {
    public func findDuplicates(force: Bool = false) {
        duplicates.find(force: force)
    }

    func resetDuplicates() {
        duplicates.reset()
    }

    public func trashDuplicateFiles(_ indices: Set<Int32>) {
        guard !indices.isEmpty else { return }
        selection = indices
        trashOperations.requestSelection()
    }

    public func collectDuplicateFiles(_ indices: Set<Int32>) {
        guard !indices.isEmpty else { return }
        addToCollection(Array(indices))
        showToast("В коллекции: \(collectionSummary)", symbol: "tray.full")
    }
}
