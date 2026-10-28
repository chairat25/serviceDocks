import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Command presets")
struct CommandPresetTests {
    @Test("adding trims, skips blanks and duplicates")
    func adding() {
        #expect(CommandPresets.adding("  yarn dev  ", to: []) == ["yarn dev"])
        #expect(CommandPresets.adding("yarn dev", to: ["yarn dev"]) == ["yarn dev"])
        #expect(CommandPresets.adding("   ", to: ["a"]) == ["a"])
        #expect(CommandPresets.adding("b", to: ["a"]) == ["a", "b"])
    }

    @Test("removing drops only that command")
    func removing() {
        #expect(CommandPresets.removing("a", from: ["a", "b"]) == ["b"])
        #expect(CommandPresets.removing("x", from: ["a"]) == ["a"])
    }

    @Test("commands used by services that are not presets, unique and in order")
    func used() {
        let used = CommandPresets.usedElsewhere(serviceCommands: ["yarn dev", " yarn dev ", "pnpm dev", "", "a"],
                                                presets: ["a"])
        #expect(used == ["yarn dev", "pnpm dev"])
    }

    @Test("old config files load without presets; presets round-trip")
    func config() throws {
        let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"services":[]}"#.utf8))
        #expect(old.commandPresets.isEmpty)
        let saved = AppConfig(services: [], commandPresets: ["yarn start:dev:uat"])
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(saved))
        #expect(decoded.commandPresets == ["yarn start:dev:uat"])
    }
}

@Suite("Edge resizing")
struct EdgeResizeTests {
    @Test("each edge changes the right dimension", arguments: [
        (TileEdge.right, 30.0, 40.0, 230.0, 100.0),
        (.left, 30.0, 40.0, 170.0, 100.0),
        (.bottom, 30.0, 40.0, 200.0, 140.0),
        (.top, 30.0, 40.0, 200.0, 60.0),
        (.bottomRight, 30.0, 40.0, 230.0, 140.0)
    ])
    func edges(edge: TileEdge, dx: Double, dy: Double, width: Double, height: Double) {
        let size = edge.resized(width: 200, height: 100, dx: dx, dy: dy)
        #expect(size.width == width)
        #expect(size.height == height)
    }
}
