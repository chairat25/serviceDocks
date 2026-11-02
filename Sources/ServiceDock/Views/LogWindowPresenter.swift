import AppKit
import SwiftUI

/// Opens a service's log window from AppKit code (a notification click), where SwiftUI's `openWindow` isn't available.
@MainActor
final class LogWindowPresenter {
    private var windows: [UUID: NSWindow] = [:]

    func show(serviceID: UUID, model: AppModel) {
        guard model.runtime(for: serviceID) != nil else { return }
        let window = windows[serviceID] ?? makeWindow(serviceID: serviceID, model: model)
        windows[serviceID] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow(serviceID: UUID, model: AppModel) -> NSWindow {
        let content = ServiceDetailView(serviceID: serviceID).environment(model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = model.name(of: serviceID)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
