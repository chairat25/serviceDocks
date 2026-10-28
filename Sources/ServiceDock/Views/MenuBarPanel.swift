import AppKit
import ServiceDockCore
import SwiftUI

enum WindowID {
    static let service = "service"
    static let editor = "editor"
}

/// What the editor window edits.
enum EditorTarget: Codable, Hashable {
    case new
    case edit(UUID)
}

/// Opens a window and brings this menu-bar-only app to the front.
@MainActor
struct WindowOpener {
    let openWindow: OpenWindowAction

    func service(_ id: UUID) { open { openWindow(id: WindowID.service, value: id) } }
    func editor(_ target: EditorTarget) { open { openWindow(id: WindowID.editor, value: target) } }

    private func open(_ action: () -> Void) {
        action()
        NSApp.activate()
    }
}

/// Which page the menu-bar panel shows.
enum PanelRoute: Equatable {
    case list
    case service(UUID, LevelFilter)
    case startupOrder
    case overview
}

struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var route = PanelRoute.list
    /// Where the back button of the current page returns to.
    @State private var backRoute = PanelRoute.list

    private static let listMaxHeight: CGFloat = 430
    private static let detailHeight: CGFloat = 560
    private static let width: CGFloat = 600

    /// The All Services page gets as much room as the screen allows.
    private static var overviewSize: CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        return CGSize(width: min(1180, screen.width - 60), height: min(760, screen.height - 80))
    }

    private func go(to newRoute: PanelRoute) {
        backRoute = route
        route = newRoute
    }

    private func goBack() {
        route = backRoute == route ? .list : backRoute
        backRoute = .list
    }

    var body: some View {
        let opener = WindowOpener(openWindow: openWindow)
        Group {
            switch route {
            case .list:
                listPage(opener: opener).frame(width: Self.width)
            case .startupOrder:
                StartupOrderPage { goBack() }
                    .frame(width: Self.width, height: Self.detailHeight)
            case .overview:
                OverviewView(onBack: goBack) { id, filter in go(to: .service(id, filter)) }
                    .frame(width: Self.overviewSize.width, height: Self.overviewSize.height)
            case .service(let id, let filter):
                if let runtime = model.runtime(for: id) {
                    ServiceDetailContent(runtime: runtime, initialFilter: filter, onBack: goBack)
                        .id("\(id)-\(filter)")
                        .frame(width: backRoute == .overview ? Self.overviewSize.width : Self.width,
                               height: backRoute == .overview ? Self.overviewSize.height : Self.detailHeight)
                } else {
                    listPage(opener: opener).frame(width: Self.width)
                }
            }
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private func listPage(opener: WindowOpener) -> some View {
        VStack(spacing: 0) {
            header(opener: opener)
            Divider().overlay(Theme.stroke)
            if model.runtimes.isEmpty {
                emptyState(opener: opener)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.runtimes) { runtime in
                            ServiceRow(runtime: runtime, opener: opener) { filter in
                                go(to: .service(runtime.id, filter))
                            }
                            if runtime.id != model.runtimes.last?.id { Divider().overlay(Theme.stroke).padding(.leading, 58) }
                        }
                    }
                }
                .frame(maxHeight: Self.listMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.storageError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
                    .padding(8)
            }
            if let startup = model.startup {
                Divider().overlay(Theme.stroke)
                StartupBanner(state: startup, onCancel: model.cancelStartup, onDismiss: model.dismissStartup)
            }
            Divider().overlay(Theme.stroke)
            footer(opener: opener)
        }
    }

    private func header(opener: WindowOpener) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: "server.rack", size: 30, tint: Theme.accent)
            Text("ServiceDock").font(.system(size: 15, weight: .semibold))
            Circle()
                .fill(model.problemCount > 0 ? Theme.red : (model.runningCount > 0 ? Theme.green : Theme.gray))
                .frame(width: 8, height: 8)
            Spacer()
            Text("\(model.runningCount) / \(model.runtimes.count) running")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            Button { opener.editor(.new) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Add service")
            Menu {
                Button("Add Service…") { opener.editor(.new) }
                Button("Startup Order…") { go(to: .startupOrder) }
                Button("All Services Monitor") { go(to: .overview) }
                Divider()
                Button("Reveal Config File") {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.defaultURL])
                }
                Divider()
                Button("Quit ServiceDock") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func emptyState(opener: WindowOpener) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox").font(.system(size: 28)).foregroundStyle(Theme.secondaryText)
            Text("No services yet").font(.system(size: 13, weight: .medium))
            Text("Add a folder and the command that starts it, e.g. yarn start:dev")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Button("Add Service…") { opener.editor(.new) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private func footer(opener: WindowOpener) -> some View {
        HStack(spacing: 4) {
            FooterButton(title: "Run All", symbol: "play.fill", action: model.runAll)
                .keyboardShortcut("r")
            FooterButton(title: "Restart All", symbol: "arrow.clockwise", action: model.restartAll)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            FooterButton(title: "Stop All", symbol: "stop.fill", action: model.stopAll)
            Spacer()
            Button { go(to: .overview) } label: {
                Label("All Services", systemImage: "square.stack.3d.up")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .card()
            }
            .buttonStyle(.plain)
        }
        .disabled(model.runtimes.isEmpty)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

struct ServiceRow: View {
    let runtime: ServiceRuntime
    let opener: WindowOpener
    /// Shows this service's detail page inside the panel.
    let onOpen: (LevelFilter) -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: runtime.config.icon, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(runtime.config.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    ErrorBadge(runtime: runtime) { onOpen(.errors) }
                    EnvChangedBadge(files: runtime.changedEnvFiles, restart: runtime.restart)
                }
                HStack(spacing: 12) {
                    Text(runtime.displayPath).lineLimit(1).truncationMode(.middle)
                    Text(runtime.config.command).lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            StatusLabel(status: runtime.status).frame(width: 110, alignment: .leading)
            primaryButton
            ServiceActionsMenu(runtime: runtime, opener: opener) { onOpen(.all) }
            Button { onOpen(.all) } label: {
                Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.borderless)
            .help("Logs & details")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(.all) }
    }

    @ViewBuilder private var primaryButton: some View {
        if runtime.status.isAlive {
            Button(action: runtime.restart) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Restart")
        } else {
            Button(action: runtime.start) { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .help("Run")
        }
    }
}

/// The "…" menu shared by rows and windows.
struct ServiceActionsMenu: View {
    @Environment(AppModel.self) private var model
    let runtime: ServiceRuntime
    let opener: WindowOpener
    /// Overrides "Show Logs"; defaults to opening the service window.
    var showLogs: (() -> Void)?

    var body: some View {
        Menu {
            Button("Run") { runtime.start() }.disabled(runtime.status.isAlive)
            Button("Restart") { runtime.restart() }
            Button("Stop") { runtime.stop() }.disabled(!runtime.status.isAlive)
            Divider()
            Button("Show Logs") { showLogs?() ?? opener.service(runtime.id) }
            Button("Open Logs in Window") { opener.service(runtime.id) }
            if let url = runtime.config.url.flatMap(URL.init(string:)) {
                Button("Open \(url.absoluteString)") { NSWorkspace.shared.open(url) }
            }
            Button("Open Folder in Finder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: runtime.directory))
            }
            Divider()
            Button("Edit…") { opener.editor(.edit(runtime.id)) }
            Button("Move Up") { model.move(id: runtime.id, by: -1) }
            Button("Move Down") { model.move(id: runtime.id, by: 1) }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
