import Foundation

extension AppModel {
    public func findSimilarImages(force: Bool = false) {
        similar.find(force: force)
    }

    func resetSimilar() {
        similar.reset()
    }

    public func trashSimilarImages(_ indices: Set<Int32>) {
        guard !indices.isEmpty else { return }
        selection = indices
        trashOperations.requestSelection()
    }

    public func collectSimilarImages(_ indices: Set<Int32>) {
        guard !indices.isEmpty else { return }
        addToCollection(Array(indices))
        showToast("В коллекции: \(collectionSummary)", symbol: "tray.full")
    }
}
