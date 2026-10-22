import Foundation

extension AppModel {
    // MARK: - Duplicates

    public func findDuplicates(force: Bool = false) {
        guard let tree, !duplicateScanning else { return }
        if !force, !duplicateGroups.isEmpty { return }

        let token = ScanCancellation()
        duplicateCancellation?.cancel()
        duplicateCancellation = token
        duplicateScanning = true
        duplicateProgress = 0
        duplicateGroups = []
        duplicateTotalWasted = 0
        duplicateCandidateCount = 0

        let options = DuplicateOptions(minimumSize: duplicateMinimumSize)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = DuplicateFinder.find(
                tree: tree,
                options: options,
                progress: { fraction in
                    DispatchQueue.main.async {
                        guard let self,
                              self.duplicateCancellation === token,
                              self.duplicateScanning else { return }
                        if fraction >= 1 || fraction - self.duplicateProgress >= 0.01 {
                            self.duplicateProgress = fraction
                        }
                    }
                },
                isCancelled: { token.isCancelled }
            )
            DispatchQueue.main.async {
                guard let self, self.duplicateCancellation === token else { return }
                self.duplicateScanning = false
                self.duplicateProgress = 1
                guard !result.cancelled else { return }
                self.duplicateGroups = result.groups
                self.duplicateTotalWasted = result.totalWasted
                self.duplicateCandidateCount = result.candidateCount
            }
        }
    }

    func resetDuplicates() {
        duplicateCancellation?.cancel()
        duplicateCancellation = nil
        duplicateGroups = []
        duplicateTotalWasted = 0
        duplicateCandidateCount = 0
        duplicateScanning = false
        duplicateProgress = 0
    }

    public func trashDuplicateFiles(_ indices: Set<Int32>) {
        guard !indices.isEmpty else { return }
        selection = indices
        requestTrashSelection()
    }

    public func collectDuplicateFiles(_ indices: Set<Int32>) {
        guard !indices.isEmpty else { return }
        addToCollection(Array(indices))
        showToast("В коллекции: \(collectionSummary)", symbol: "tray.full")
    }
}
