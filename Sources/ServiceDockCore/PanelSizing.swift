import Foundation

/// Size maths for the resizable menu-bar panel pages.
public enum PanelSizing {
    public struct Limits: Equatable, Sendable {
        public let minWidth: Double
        public let minHeight: Double
        public let maxWidth: Double
        public let maxHeight: Double

        public init(minWidth: Double, minHeight: Double, maxWidth: Double, maxHeight: Double) {
            self.minWidth = minWidth
            self.minHeight = minHeight
            self.maxWidth = max(minWidth, maxWidth)
            self.maxHeight = max(minHeight, maxHeight)
        }
    }

    /// The size after dragging the bottom-right corner by (dx, dy), kept within `limits`.
    public static func resized(width: Double, height: Double, dx: Double, dy: Double,
                               limits: Limits) -> (width: Double, height: Double) {
        (min(max(width + dx, limits.minWidth), limits.maxWidth),
         min(max(height + dy, limits.minHeight), limits.maxHeight))
    }
}

extension PanelSizing {
    public struct Rect: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Moves `frame` (same size) so it sits inside `screen` with `margin` to spare; the left/bottom
    /// edges win when it is bigger than the screen.
    public static func keptOnScreen(_ frame: Rect, screen: Rect, margin: Double) -> Rect {
        let x = max(min(frame.x, screen.x + screen.width - margin - frame.width), screen.x + margin)
        let y = max(min(frame.y, screen.y + screen.height - margin - frame.height), screen.y + margin)
        return Rect(x: x, y: y, width: frame.width, height: frame.height)
    }
}
