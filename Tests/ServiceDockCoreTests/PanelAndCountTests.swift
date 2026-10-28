import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Clearing error counts")
struct ResetCountsTests {
    @Test("resets error and warn counts but keeps the log lines")
    func keepsLines() {
        var buffer = LogBuffer(capacity: 10)
        buffer.append([LogLine(id: 1, serviceID: UUID(), date: Date(), text: "boom", level: .error),
                       LogLine(id: 2, serviceID: UUID(), date: Date(), text: "hmm", level: .warn)])
        buffer.resetCounts()
        #expect(buffer.errorCount == 0)
        #expect(buffer.warnCount == 0)
        #expect(buffer.lines.count == 2)
    }
}

@Suite("Panel sizing")
struct PanelSizingTests {
    let limits = PanelSizing.Limits(minWidth: 400, minHeight: 300, maxWidth: 1400, maxHeight: 900)

    @Test("applies a drag and clamps to the limits", arguments: [
        (600.0, 500.0, 100.0, 50.0, 700.0, 550.0),
        (600.0, 500.0, -500.0, -500.0, 400.0, 300.0),
        (600.0, 500.0, 5000.0, 5000.0, 1400.0, 900.0)
    ])
    func drag(width: Double, height: Double, dx: Double, dy: Double, expectedWidth: Double, expectedHeight: Double) {
        let size = PanelSizing.resized(width: width, height: height, dx: dx, dy: dy, limits: limits)
        #expect(size.width == expectedWidth)
        #expect(size.height == expectedHeight)
    }

    @Test("a saved size outside the limits (smaller screen) is pulled back in")
    func savedSize() {
        let size = PanelSizing.resized(width: 3000, height: 100, dx: 0, dy: 0, limits: limits)
        #expect(size.width == 1400)
        #expect(size.height == 300)
    }
}

@Suite("Keeping the panel on screen")
struct OnScreenTests {
    let screen = PanelSizing.Rect(x: 0, y: 0, width: 1440, height: 870)

    @Test("a panel hanging off the left edge is moved right")
    func leftEdge() {
        let frame = PanelSizing.Rect(x: -300, y: 100, width: 1200, height: 700)
        #expect(PanelSizing.keptOnScreen(frame, screen: screen, margin: 8).x == 8)
    }

    @Test("a panel hanging off the right edge is moved left")
    func rightEdge() {
        let frame = PanelSizing.Rect(x: 900, y: 100, width: 800, height: 500)
        #expect(PanelSizing.keptOnScreen(frame, screen: screen, margin: 8).x == 632)
    }

    @Test("a panel below the bottom edge is moved up; one already inside stays put")
    func bottomAndInside() {
        #expect(PanelSizing.keptOnScreen(.init(x: 10, y: -50, width: 400, height: 300), screen: screen, margin: 8).y == 8)
        let inside = PanelSizing.Rect(x: 100, y: 100, width: 400, height: 300)
        #expect(PanelSizing.keptOnScreen(inside, screen: screen, margin: 8) == inside)
    }
}
