import Foundation

/// Layout maths for the All Services log grid: as many columns as fit, balanced so the
/// last row is not left with one lonely tile (4 services → 2×2, not 3+1).
public enum TileGrid {
    public static func columns(count: Int, width: Double, minTileWidth: Double = 380) -> Int {
        guard count > 0 else { return 1 }
        let fit = max(1, Int(width / minTileWidth))
        let rows = Int((Double(count) / Double(min(fit, count))).rounded(.up))
        return Int((Double(count) / Double(rows)).rounded(.up))
    }

    public static func rows(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        return (count + columns - 1) / columns
    }

    /// Splits the available height between rows; below `minHeight` the grid scrolls instead.
    public static func tileHeight(available: Double, rows: Int, spacing: Double, minHeight: Double) -> Double {
        guard rows > 0 else { return available }
        let share = (available - spacing * Double(rows - 1)) / Double(rows)
        return max(share, minHeight)
    }
}
