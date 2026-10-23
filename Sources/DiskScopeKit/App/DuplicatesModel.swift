import Combine
import Foundation

/// Owns the duplicate search state and background hashing.
@MainActor
public final class DuplicatesModel: ObservableObject {
    @Published public internal(set) var groups: [DuplicateGroup] = []
    @Published public internal(set) var totalWasted: Int64 = 0
    @Published public internal(set) var candidateCount = 0
    @Published public internal(set) var scanning = false
    @Published public internal(set) var progress: Double = 0
    @Published public var minimumSize: Int64 = 1_000_000 {
        didSet { reset() }
    }

    private var treeProvider: () -> ScanTree? = { nil }
    private var cancellation: ScanCancellation?

    public init() {}

    func attach(treeProvider: @escaping () -> ScanTree?) {
        self.treeProvider = treeProvider
    }

    public func find(force: Bool = false) {
        guard let tree = treeProvider(), !scanning else { return }
        if !force, !groups.isEmpty { return }

        let token = ScanCancellation()
        cancellation?.cancel()
        cancellation = token
        scanning = true
        progress = 0
        groups = []
        totalWasted = 0
        candidateCount = 0

        let options = DuplicateOptions(minimumSize: minimumSize)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = DuplicateFinder.find(
                tree: tree,
                options: options,
                progress: { fraction in
                    DispatchQueue.main.async {
                        guard let self,
                              self.cancellation === token,
                              self.scanning else { return }
                        if fraction >= 1 || fraction - self.progress >= 0.01 {
                            self.progress = fraction
                        }
                    }
                },
                isCancelled: { token.isCancelled }
            )
            DispatchQueue.main.async {
                guard let self, self.cancellation === token else { return }
                self.scanning = false
                self.progress = 1
                guard !result.cancelled else { return }
                self.groups = result.groups
                self.totalWasted = result.totalWasted
                self.candidateCount = result.candidateCount
            }
        }
    }

    public func reset() {
        cancellation?.cancel()
        cancellation = nil
        groups = []
        totalWasted = 0
        candidateCount = 0
        scanning = false
        progress = 0
    }

    func preview(_ groups: [DuplicateGroup]) {
        reset()
        self.groups = groups
        totalWasted = groups.reduce(0) { $0 + $1.wastedBytes }
        candidateCount = groups.reduce(0) { $0 + $1.files.count }
        progress = 1
    }
}
