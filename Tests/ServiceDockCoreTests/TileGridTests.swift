import Testing
@testable import ServiceDockCore

@Suite("Tile grid")
struct TileGridTests {
    @Test("always at least one column, even with nothing to show")
    func empty() {
        #expect(TileGrid.columns(count: 0, width: 1200) == 1)
        #expect(TileGrid.rows(count: 0, columns: 1) == 0)
    }

    @Test("picks balanced columns for the width", arguments: [
        (1, 1200.0, 1), (2, 1200.0, 2), (4, 1200.0, 2), (5, 1200.0, 3), (6, 1200.0, 3),
        (6, 500.0, 1), (6, 800.0, 2), (7, 1200.0, 3), (10, 1200.0, 3), (10, 1600.0, 4), (3, 3000.0, 3)
    ])
    func balanced(count: Int, width: Double, expected: Int) {
        #expect(TileGrid.columns(count: count, width: width, minTileWidth: 380) == expected)
    }

    @Test("counts rows")
    func rows() {
        #expect(TileGrid.rows(count: 6, columns: 3) == 2)
        #expect(TileGrid.rows(count: 7, columns: 3) == 3)
    }

    @Test("tiles share the height but never get shorter than the minimum")
    func tileHeight() {
        #expect(TileGrid.tileHeight(available: 700, rows: 2, spacing: 10, minHeight: 200) == 345)
        #expect(TileGrid.tileHeight(available: 300, rows: 3, spacing: 10, minHeight: 200) == 200)
        #expect(TileGrid.tileHeight(available: 500, rows: 0, spacing: 10, minHeight: 200) == 500)
    }
}
