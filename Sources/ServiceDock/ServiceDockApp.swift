import AppKit
import SwiftUI

@main
struct ServiceDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel().environment(appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Service", id: WindowID.service, for: UUID.self) { $id in
            if let id {
                ServiceDetailView(serviceID: id).environment(appDelegate.model)
            }
        }
        .defaultSize(width: 760, height: 560)

        WindowGroup("Service Editor", id: WindowID.editor, for: EditorTarget.self) { $target in
            if let target {
                ServiceEditorView(target: target).environment(appDelegate.model)
            }
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.problemCount > 0 ? "exclamationmark.triangle.fill" : "server.rack")
            if !model.runtimes.isEmpty {
                Text("\(model.runningCount)/\(model.runtimes.count)")
            }
        }
    }
}

/// Owns the model so it outlives every scene, and stops all services on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var signalSources: [DispatchSourceSignal] = []

    /// `kill` / `pkill` / Ctrl-C / logout deliver these; stop the services before dying.
    func applicationDidFinishLaunching(_ notification: Notification) {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.model.shutdownAll()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdownAll()
    }
}
