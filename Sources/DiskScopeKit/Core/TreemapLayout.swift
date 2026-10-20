import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls, Huizing, van Wijk).
public enum TreemapLayout {
    /// Returns one rectangle per input value, in the same order.
    /// Rectangles tile `rect` exactly (up to floating point error).
    public static func layout(values: [Double], in rect: CGRect) -> [CGRect] {
        guard !values.isEmpty, rect.width > 0, rect.height > 0 else {
            return Array(repeating: .zero, count: values.count)
        }
        var items: [Item] = []
        var total: Double = 0
        for (index, value) in values.enumerated() where value > 0 {
            items.append(Item(index: index, area: value))
            total += value
        }
        guard total > 0 else {
            return Array(repeating: .zero, count: values.count)
        }

        items.sort { $0.area > $1.area }
        let scale = Double(rect.width * rect.height) / total
        for index in items.indices { items[index].area *= scale }

        var result = [CGRect](repeating: .zero, count: values.count)
        var free = rect
        var row: [Item] = []
        var rowArea: Double = 0
        var cursor = 0

        func worstRatio(_ row: [Item], _ rowArea: Double, _ side: Double) -> Double {
            guard let minArea = row.map(\.area).min(),
                  let maxArea = row.map(\.area).max(),
                  minArea > 0, side > 0 else { return .greatestFiniteMagnitude }
            let sideSquared = side * side
            let sumSquared = rowArea * rowArea
            return max(sideSquared * maxArea / sumSquared, sumSquared / (sideSquared * minArea))
        }

        func place(_ row: [Item], _ rowArea: Double) {
            guard !row.isEmpty, rowArea > 0 else { return }
            let side = Double(min(free.width, free.height))
            guard side > 0 else { return }
            let thickness = rowArea / side
            if free.width >= free.height {
                var y = free.minY
                for item in row {
                    let height = CGFloat(item.area / thickness)
                    result[item.index] = CGRect(x: free.minX, y: y, width: thickness, height: height)
                    y += height
                }
                free = CGRect(
                    x: free.minX + CGFloat(thickness),
                    y: free.minY,
                    width: max(0, free.width - CGFloat(thickness)),
                    height: free.height
                )
            } else {
                var x = free.minX
                for item in row {
                    let width = CGFloat(item.area / thickness)
                    result[item.index] = CGRect(x: x, y: free.minY, width: width, height: thickness)
                    x += width
                }
                free = CGRect(
                    x: free.minX,
                    y: free.minY + CGFloat(thickness),
                    width: free.width,
                    height: max(0, free.height - CGFloat(thickness))
                )
            }
        }

        while cursor < items.count {
            let side = Double(min(free.width, free.height))
            guard side > 0 else { break }
            let next = items[cursor]
            let candidate = row + [next]
            let worstWith = worstRatio(candidate, rowArea + next.area, side)
            let worstCurrent = row.isEmpty ? Double.greatestFiniteMagnitude : worstRatio(row, rowArea, side)
            if row.isEmpty || worstWith <= worstCurrent {
                row = candidate
                rowArea += next.area
                cursor += 1
            } else {
                place(row, rowArea)
                row = []
                rowArea = 0
            }
        }
        if !row.isEmpty {
            place(row, rowArea)
        }
        return result
    }

    private struct Item {
        let index: Int
        var area: Double
    }
}
