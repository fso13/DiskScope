import Foundation
import Vision

public struct SimilarImage: Identifiable, Hashable, Sendable {
    public let index: Int32
    public let path: String
    public let relativePath: String
    public let size: Int64
    public let modified: Date?

    public var id: Int32 { index }

    public init(index: Int32, path: String, relativePath: String, size: Int64, modified: Date?) {
        self.index = index
        self.path = path
        self.relativePath = relativePath
        self.size = size
        self.modified = modified
    }
}

public struct SimilarImageGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let images: [SimilarImage]

    public var totalSize: Int64 { images.reduce(0) { $0 + $1.size } }

    public init(id: String, images: [SimilarImage]) {
        self.id = id
        self.images = images
    }
}

public struct SimilarImageOptions: Sendable, Equatable {
    public var minimumSize: Int64
    public var maximumImages: Int
    public var threshold: Float
    public var maxGroups: Int

    public init(
        minimumSize: Int64 = 100_000,
        maximumImages: Int = 600,
        threshold: Float = 0.35,
        maxGroups: Int = 200
    ) {
        self.minimumSize = max(minimumSize, 0)
        self.maximumImages = max(maximumImages, 2)
        self.threshold = min(max(threshold, 0.05), 1.5)
        self.maxGroups = max(maxGroups, 1)
    }
}

public struct SimilarImageState: Sendable {
    public var groups: [SimilarImageGroup] = []
    public var scanning = false
    public var progress: Double = 0
    public var candidateCount = 0
    public var scannedCount = 0

    public init() {}
}

public struct SimilarImageResult: Sendable {
    public let groups: [SimilarImageGroup]
    public let candidateCount: Int
    public let scannedCount: Int
    public let skippedCount: Int
    public let truncated: Bool
    public let cancelled: Bool

    public init(
        groups: [SimilarImageGroup],
        candidateCount: Int,
        scannedCount: Int,
        skippedCount: Int,
        truncated: Bool,
        cancelled: Bool
    ) {
        self.groups = groups
        self.candidateCount = candidateCount
        self.scannedCount = scannedCount
        self.skippedCount = skippedCount
        self.truncated = truncated
        self.cancelled = cancelled
    }

    public static let empty = SimilarImageResult(
        groups: [], candidateCount: 0, scannedCount: 0,
        skippedCount: 0, truncated: false, cancelled: false
    )
}

public struct ImageFeature: Sendable {
    public let index: Int32
    public let vector: [Float]

    public init(index: Int32, vector: [Float]) {
        self.index = index
        self.vector = vector
    }
}

public enum SimilarImageClusterer {
    /// Greedy clustering by Euclidean distance to each cluster representative.
    public static func cluster(
        _ features: [ImageFeature],
        threshold: Float,
        maxGroups: Int = 200
    ) -> [[Int32]] {
        guard threshold > 0 else { return [] }
        var clusters: [[ImageFeature]] = []
        for feature in features where !feature.vector.isEmpty {
            var bestCluster: Int?
            var bestDistance = threshold
            for (offset, cluster) in clusters.enumerated() {
                guard let representative = cluster.first else { continue }
                let distance = euclidean(feature.vector, representative.vector)
                guard distance.isFinite else { continue }
                if distance < bestDistance {
                    bestDistance = distance
                    bestCluster = offset
                }
            }
            if let bestCluster {
                clusters[bestCluster].append(feature)
            } else {
                clusters.append([feature])
            }
        }
        var groups = clusters.filter { $0.count > 1 }.map { $0.map(\.index) }
        groups.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            return ($0.first ?? 0) < ($1.first ?? 0)
        }
        if groups.count > maxGroups {
            groups = Array(groups.prefix(maxGroups))
        }
        return groups
    }

    private static func euclidean(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count else { return .infinity }
        var sum: Float = 0
        for index in lhs.indices {
            let delta = lhs[index] - rhs[index]
            sum += delta * delta
        }
        return sqrt(sum)
    }
}

public enum SimilarImageFinder {
    public static func find(
        tree: ScanTree,
        options: SimilarImageOptions = SimilarImageOptions(),
        progress: ((Double) -> Void)? = nil,
        isCancelled: (() -> Bool)? = nil
    ) -> SimilarImageResult {
        let candidates = candidateIndices(tree: tree, options: options)
        guard candidates.count > 1 else { return .empty }

        var features: [ImageFeature] = []
        var skipped = 0
        for (offset, index) in candidates.enumerated() {
            if isCancelled?() == true {
                return SimilarImageResult(
                    groups: [], candidateCount: candidates.count,
                    scannedCount: features.count, skippedCount: skipped,
                    truncated: false, cancelled: true
                )
            }
            if let vector = featurePrint(url: tree.url(of: index)) {
                features.append(ImageFeature(index: index, vector: vector))
            } else {
                skipped += 1
            }
            progress?(Double(offset + 1) / Double(candidates.count))
        }

        let groupedIndices = SimilarImageClusterer.cluster(
            features,
            threshold: options.threshold,
            maxGroups: Int.max
        )
        let truncated = groupedIndices.count > options.maxGroups
        let groups = groupedIndices.prefix(options.maxGroups).map { indices -> SimilarImageGroup in
            let images = indices.map { index in
                SimilarImage(
                    index: index,
                    path: tree.path(of: index),
                    relativePath: tree.relativePath(of: index),
                    size: tree.node(index).size,
                    modified: tree.modified(of: index)
                )
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            return SimilarImageGroup(id: "similar-\(indices.first ?? 0)", images: images)
        }
        .sorted {
            if $0.images.count != $1.images.count { return $0.images.count > $1.images.count }
            return $0.totalSize > $1.totalSize
        }

        progress?(1)
        return SimilarImageResult(
            groups: groups,
            candidateCount: candidates.count,
            scannedCount: features.count,
            skippedCount: skipped,
            truncated: truncated,
            cancelled: false
        )
    }

    static func candidateIndices(tree: ScanTree, options: SimilarImageOptions) -> [Int32] {
        var result: [Int32] = []
        var stack: [Int32] = [0]
        while let index = stack.popLast() {
            let node = tree.node(index)
            switch node.nodeKind {
            case .directory:
                for child in tree.children(of: index) { stack.append(child) }
            case .package, .aggregate, .symlink:
                continue
            case .file:
                guard !node.isHardLink,
                      node.size >= options.minimumSize,
                      tree.category(of: index) == .image else { continue }
                result.append(index)
            }
        }
        result.sort { tree.node($0).size > tree.node($1).size }
        if result.count > options.maximumImages {
            result = Array(result.prefix(options.maximumImages))
        }
        return result
    }

    private static func featurePrint(url: URL) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNFeaturePrintObservation,
              observation.elementCount > 0 else {
            return nil
        }
        let data = observation.data as Data
        let count = observation.elementCount
        switch observation.elementType {
        case .float:
            return data.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self).prefix(count))
            }
        case .double:
            return data.withUnsafeBytes { raw in
                raw.bindMemory(to: Double.self).prefix(count).map(Float.init)
            }
        default:
            return nil
        }
    }
}
