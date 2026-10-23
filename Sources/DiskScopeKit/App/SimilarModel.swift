import Combine
import Foundation

/// Owns similar-image search state, options and Vision progress.
@MainActor
public final class SimilarModel: ObservableObject {
    @Published public var options = SimilarImageOptions() {
        didSet { reset() }
    }
    @Published public internal(set) var state = SimilarImageState()

    private var treeProvider: () -> ScanTree? = { nil }
    private var cancellation: ScanCancellation?

    public init() {}

    func attach(treeProvider: @escaping () -> ScanTree?) {
        self.treeProvider = treeProvider
    }

    public func find(force: Bool = false) {
        guard let tree = treeProvider(), !state.scanning else { return }
        if !force, !state.groups.isEmpty { return }

        let token = ScanCancellation()
        cancellation?.cancel()
        cancellation = token
        state = SimilarImageState()
        state.scanning = true
        state.candidateCount = 0

        let options = options
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SimilarImageFinder.find(
                tree: tree,
                options: options,
                progress: { fraction in
                    DispatchQueue.main.async {
                        guard let self,
                              self.cancellation === token,
                              self.state.scanning else { return }
                        if fraction >= 1 || fraction - self.state.progress >= 0.01 {
                            self.state.progress = fraction
                        }
                    }
                },
                isCancelled: { token.isCancelled }
            )
            DispatchQueue.main.async {
                guard let self, self.cancellation === token else { return }
                self.state.scanning = false
                self.state.progress = 1
                guard !result.cancelled else { return }
                self.state.groups = result.groups
                self.state.candidateCount = result.candidateCount
                self.state.scannedCount = result.scannedCount
            }
        }
    }

    public func reset() {
        cancellation?.cancel()
        cancellation = nil
        state = SimilarImageState()
    }

    func preview(_ groups: [SimilarImageGroup]) {
        state = SimilarImageState()
        state.groups = groups
        state.candidateCount = groups.reduce(0) { $0 + $1.images.count }
        state.scannedCount = state.candidateCount
        state.progress = 1
    }
}
