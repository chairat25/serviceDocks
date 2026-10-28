import Foundation

/// A tile's chosen size in the All Services grid. `nil` fields mean "automatic".
public struct TileSpec: Equatable, Sendable {
    public let span: Int?
    public let height: Double?

    public init(span: Int? = nil, height: Double? = nil) {
        self.span = span
        self.height = height
    }
}

public struct TileFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// Packs tiles of different widths (in whole columns) and heights into rows, in order.
/// A tile that does not fit in what is left of a row starts the next one; the tallest tile
/// sets its row's height so rows stay aligned.
public enum TilePacking {
    public struct Layout: Equatable, Sendable {
        public let frames: [TileFrame]
        public let totalHeight: Double
    }

    public static func layout(tiles: [TileSpec], columns: Int, width: Double, spacing: Double,
                              autoHeight: Double) -> Layout {
        let columns = max(1, columns)
        let columnWidth = (width - spacing * Double(columns - 1)) / Double(columns)
        let rows = packRows(spans: tiles.map { clampedSpan($0.span, columns: columns) }, columns: columns)

        var frames: [TileFrame] = []
        var y = 0.0
        for row in rows {
            let rowHeight = row.map { tiles[$0.index].height ?? autoHeight }.max() ?? autoHeight
            frames += row.map { slot in
                TileFrame(x: Double(slot.column) * (columnWidth + spacing), y: y,
                          width: Double(slot.span) * columnWidth + Double(slot.span - 1) * spacing, height: rowHeight)
            }
            y += rowHeight + spacing
        }
        return Layout(frames: frames, totalHeight: rows.isEmpty ? 0 : y - spacing)
    }

    /// Whole columns closest to a dragged width, between 1 and `columns`.
    public static func span(forWidth dragged: Double, columns: Int, width: Double, spacing: Double) -> Int {
        let columns = max(1, columns)
        let columnWidth = (width - spacing * Double(columns - 1)) / Double(columns)
        let span = Int(((dragged + spacing) / (columnWidth + spacing)).rounded())
        return min(max(span, 1), columns)
    }

    private struct Slot {
        let index: Int
        let column: Int
        let span: Int
    }

    private static func clampedSpan(_ span: Int?, columns: Int) -> Int {
        min(max(span ?? 1, 1), columns)
    }

    private static func packRows(spans: [Int], columns: Int) -> [[Slot]] {
        spans.enumerated().reduce(into: [[Slot]]()) { rows, item in
            let used = rows.last.map { $0.reduce(0) { $0 + $1.span } } ?? columns
            if used + item.element <= columns, !rows.isEmpty {
                rows[rows.count - 1].append(Slot(index: item.offset, column: used, span: item.element))
            } else {
                rows.append([Slot(index: item.offset, column: 0, span: item.element)])
            }
        }
    }
}

extension Array where Element: Equatable {
    /// Returns a copy with `item` moved next to `target`: in front of it, or right after it when `after` is true.
    /// Unknown items or dropping an item on itself leave the order unchanged.
    public func moving(_ item: Element, onto target: Element, after: Bool = false) -> [Element] {
        guard item != target, contains(item), contains(target) else { return self }
        let rest = filter { $0 != item }
        guard let targetIndex = rest.firstIndex(of: target) else { return self }
        let insertAt = after ? targetIndex + 1 : targetIndex
        return Array(rest[..<insertAt]) + [item] + Array(rest[insertAt...])
    }
}

/// Which part of a tile is being dragged to resize it.
public enum TileEdge: CaseIterable, Sendable {
    case left, right, top, bottom, bottomRight

    /// New size after dragging this edge by (dx, dy); left/top edges grow when dragged outwards.
    public func resized(width: Double, height: Double, dx: Double, dy: Double) -> (width: Double, height: Double) {
        switch self {
        case .left: (width - dx, height)
        case .right: (width + dx, height)
        case .top: (width, height - dy)
        case .bottom: (width, height + dy)
        case .bottomRight: (width + dx, height + dy)
        }
    }
}
