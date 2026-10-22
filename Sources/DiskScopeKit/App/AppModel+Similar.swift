import Foundation

extension AppModel {
    // MARK: - Similar images

    public func findSimilarImages(force: Bool = false) {
        guard let tree, !similarState.scanning else { return }
        if !force, !similarState.groups.isEmpty { return }

        let token = ScanCancellation()
        similarCancellation?.cancel()
        similarCancellation = token
        similarState = SimilarImageState()
        similarState.scanning = true
        similarState.candidateCount = 0

        let options = similarOptions
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SimilarImageFinder.find(
                tree: tree,
                options: options,
                progress: { fraction in
                    DispatchQueue.main.async {
                        guard let self,
                              self.similarCancellation === token,
                              self.similarState.scanning else { return }
                        if fraction >= 1 || fraction - self.similarState.progress >= 0.01 {
                            self.similarState.progress = fraction
                        }
                    }
                },
                isCancelled: { token.isCancelled }
            )
            DispatchQueue.main.async {
                guard let self, self.similarCancellation === token else { return }
                self.similarState.scanning = false
                self.similarState.progress = 1
                guard !result.cancelled else { return }
                self.similarState.groups = result.groups
                self.similarState.candidateCount = result.candidateCount
                self.similarState.scannedCount = result.scannedCount
            }
        }
    }

    func resetSimilar() {
        similarCancellation?.cancel()
        similarCancellation = nil
        similarState = SimilarImageState()
    }

    public func trashSimilarImages(_ indices: Set<Int32>) {
        guard !indices.isEmpty else { return }
        selection = indices
        requestTrashSelection()
    }

    public func collectSimilarImages(_ indices: Set<Int32>) {
        guard !indices.isEmpty else { return }
        addToCollection(Array(indices))
        showToast("В коллекции: \(collectionSummary)", symbol: "tray.full")
    }
}
