import CoreGraphics

public enum TreemapDirection: Sendable {
    case left, right, up, down
}

public enum TreemapNavigation {
    /// Returns the nearest clickable cell in the requested direction.
    /// Coordinates are in SwiftUI's top-left origin space.
    public static func nextNode(
        from current: Int32?,
        cells: [TreemapCell],
        direction: TreemapDirection
    ) -> Int32? {
        let clickable = cells.filter { $0.node != nil && $0.depth <= 2 }
        guard !clickable.isEmpty else { return nil }

        let origin: CGPoint
        if let current, let cell = clickable.first(where: { $0.node == current }) {
            origin = CGPoint(x: cell.rect.midX, y: cell.rect.midY)
        } else {
            let minX = clickable.map(\.rect.minX).min() ?? 0
            let maxX = clickable.map(\.rect.maxX).max() ?? 0
            let minY = clickable.map(\.rect.minY).min() ?? 0
            let maxY = clickable.map(\.rect.maxY).max() ?? 0
            origin = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        }

        var best: (node: Int32, score: CGFloat)?
        for cell in clickable {
            guard let node = cell.node, node != current else { continue }
            let center = CGPoint(x: cell.rect.midX, y: cell.rect.midY)
            let dx = center.x - origin.x
            let dy = center.y - origin.y
            let primary: CGFloat
            let perpendicular: CGFloat
            switch direction {
            case .right:
                guard dx > 0.5 else { continue }
                primary = dx
                perpendicular = abs(dy)
            case .left:
                guard dx < -0.5 else { continue }
                primary = -dx
                perpendicular = abs(dy)
            case .down:
                guard dy > 0.5 else { continue }
                primary = dy
                perpendicular = abs(dx)
            case .up:
                guard dy < -0.5 else { continue }
                primary = -dy
                perpendicular = abs(dx)
            }
            let score = primary + perpendicular * 2
            if best == nil || score < best!.score {
                best = (node, score)
            }
        }
        return best?.node
    }
}
