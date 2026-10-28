import AppKit
import ServiceDockCore
import SwiftUI

/// The menu-bar panel hangs from its status item, so a wide page can run off the left or right
/// edge of the screen. This watches the panel's window and slides it back inside the visible area.
struct KeepOnScreen: NSViewRepresentable {
    private static let margin = 8.0

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        func attach(to window: NSWindow?) {
            guard let window, window !== self.window else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            self.window = window
            observers = [NSWindow.didResizeNotification, NSWindow.didMoveNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clamp() }
                }
            }
            clamp()
        }

        private func clamp() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            let frame = window.frame
            let visible = screen.visibleFrame
            let kept = PanelSizing.keptOnScreen(
                PanelSizing.Rect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                screen: PanelSizing.Rect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height),
                margin: KeepOnScreen.margin
            )
            guard kept.x != frame.minX || kept.y != frame.minY else { return }
            window.setFrameOrigin(NSPoint(x: kept.x, y: kept.y))
        }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
