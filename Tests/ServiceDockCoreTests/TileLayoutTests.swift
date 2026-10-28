import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Tile packing")
struct TilePackingTests {
    @Test("auto tiles fill rows like a plain grid")
    func autoTiles() {
        let layout = TilePacking.layout(tiles: Array(repeating: TileSpec(), count: 4), columns: 2, width: 410,
                                        spacing: 10, autoHeight: 100)
        #expect(layout.frames.map(\.x) == [0, 210, 0, 210])
        #expect(layout.frames.map(\.y) == [0, 0, 110, 110])
        #expect(layout.frames.allSatisfy { $0.width == 200 && $0.height == 100 })
        #expect(layout.totalHeight == 210)
    }

    @Test("a wide tile spans columns and wraps when it does not fit")
    func spans() {
        let tiles = [TileSpec(), TileSpec(span: 2), TileSpec()]
        let layout = TilePacking.layout(tiles: tiles, columns: 2, width: 410, spacing: 10, autoHeight: 100)
        #expect(layout.frames[1].x == 0)
        #expect(layout.frames[1].y == 110)
        #expect(layout.frames[1].width == 410)
        #expect(layout.frames[2].y == 220)
    }

    @Test("a span larger than the grid is clamped")
    func clampSpan() {
        let layout = TilePacking.layout(tiles: [TileSpec(span: 5)], columns: 3, width: 320, spacing: 10, autoHeight: 50)
        #expect(layout.frames[0].width == 320)
    }

    @Test("the tallest tile sets the row height")
    func rowHeight() {
        let tiles = [TileSpec(height: 300), TileSpec(), TileSpec()]
        let layout = TilePacking.layout(tiles: tiles, columns: 2, width: 410, spacing: 10, autoHeight: 100)
        #expect(layout.frames[0].height == 300)
        #expect(layout.frames[1].height == 300)
        #expect(layout.frames[2].y == 310)
        #expect(layout.totalHeight == 410)
    }

    @Test("snaps a dragged width to whole columns")
    func snapSpan() {
        #expect(TilePacking.span(forWidth: 190, columns: 3, width: 620, spacing: 10) == 1)
        #expect(TilePacking.span(forWidth: 330, columns: 3, width: 620, spacing: 10) == 2)
        #expect(TilePacking.span(forWidth: 5000, columns: 3, width: 620, spacing: 10) == 3)
        #expect(TilePacking.span(forWidth: -20, columns: 3, width: 620, spacing: 10) == 1)
    }

    @Test("no tiles → no height")
    func empty() {
        #expect(TilePacking.layout(tiles: [], columns: 2, width: 400, spacing: 10, autoHeight: 100).totalHeight == 0)
    }
}

@Suite("Reordering")
struct ReorderTests {
    @Test("moves an item in front of the target", arguments: [
        ("a", "c", ["b", "a", "c", "d"]),
        ("d", "a", ["d", "a", "b", "c"]),
        ("a", "a", ["a", "b", "c", "d"]),
        ("x", "b", ["a", "b", "c", "d"])
    ])
    func move(item: String, target: String, expected: [String]) {
        #expect(["a", "b", "c", "d"].moving(item, onto: target) == expected)
    }

    @Test("dropping on a later item lands after it when moving forward")
    func forward() {
        #expect(["a", "b", "c"].moving("a", onto: "c", after: true) == ["b", "c", "a"])
    }
}

@Suite("Tile size config")
struct TileSizeConfigTests {
    @Test("old config files load without tile sizes")
    func decodesOld() throws {
        let json = #"{"id":"6F1C2D2E-0000-0000-0000-000000000000","name":"a","path":"/","command":"x","icon":"cpu"}"#
        let config = try JSONDecoder().decode(ServiceConfig.self, from: Data(json.utf8))
        #expect(config.tileSpan == nil)
        #expect(config.tileHeight == nil)
    }

    @Test("tile sizes round-trip")
    func roundTrip() throws {
        var config = ServiceConfig(name: "a", path: "/", command: "x")
        config.tileSpan = 2
        config.tileHeight = 320
        let decoded = try JSONDecoder().decode(ServiceConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.tileSpan == 2)
        #expect(decoded.tileHeight == 320)
    }
}
