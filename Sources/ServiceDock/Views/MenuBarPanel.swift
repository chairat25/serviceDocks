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

/// Set by the menu-bar panel so "Edit…" opens as a page of the panel instead of a new window.
extension EnvironmentValues {
    @Entry var editInPanel: ((EditorTarget) -> Void)?
}

/// Which page the menu-bar panel shows.
enum PanelRoute: Equatable {
    case list
    case service(UUID, LevelFilter)
    case startupOrder
    case overview
    case editor(EditorTarget)
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

    /// Sizes chosen with the resize grip; 0 = default. Each kind of page remembers its own.
    @AppStorage("panel.list.width") private var listWidth = 0.0
    @AppStorage("panel.list.height") private var listHeight = 0.0
    @AppStorage("panel.detail.width") private var detailWidth = 0.0
    @AppStorage("panel.detail.height") private var detailHeight = 0.0
    @AppStorage("panel.overview.width") private var overviewWidth = 0.0
    @AppStorage("panel.overview.height") private var overviewHeight = 0.0

    private static var screenSize: CGSize {
        NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
    }

    /// The All Services page gets as much room as the screen allows.
    private static var defaultOverviewSize: CGSize {
        CGSize(width: min(1180, screenSize.width - 60), height: min(760, screenSize.height - 80))
    }

    private static var limits: PanelSizing.Limits {
        PanelSizing.Limits(minWidth: 480, minHeight: 240,
                           maxWidth: screenSize.width - 16, maxHeight: screenSize.height - 60)
    }

    private func size(_ width: Double, _ height: Double, default fallback: CGSize) -> CGSize {
        let size = PanelSizing.resized(width: width > 0 ? width : fallback.width,
                                       height: height > 0 ? height : fallback.height,
                                       dx: 0, dy: 0, limits: Self.limits)
        return CGSize(width: size.width, height: size.height)
    }

    private var listSize: CGSize { size(listWidth, listHeight, default: CGSize(width: Self.width, height: Self.listMaxHeight)) }
    private var detailSize: CGSize {
        size(detailWidth, detailHeight, default: CGSize(width: Self.width, height: Self.detailHeight))
    }
    private var overviewSize: CGSize { size(overviewWidth, overviewHeight, default: Self.defaultOverviewSize) }

    /// Which stored size the grip changes on the current page.
    private var resizeTarget: (width: Binding<Double>, height: Binding<Double>, current: CGSize) {
        switch route {
        case .list: ($listWidth, $listHeight, listSize)
        case .overview: ($overviewWidth, $overviewHeight, overviewSize)
        case .service where backRoute == .overview: ($overviewWidth, $overviewHeight, overviewSize)
        case .service, .startupOrder, .editor: ($detailWidth, $detailHeight, detailSize)
        }
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
                listPage(opener: opener).frame(width: listSize.width)
            case .startupOrder:
                StartupOrderPage { goBack() }
                    .frame(width: detailSize.width, height: detailSize.height)
            case .overview:
                OverviewView(onBack: goBack) { id, filter in go(to: .service(id, filter)) }
                    .frame(width: overviewSize.width, height: overviewSize.height)
            case .service(let id, let filter):
                if let runtime = model.runtime(for: id) {
                    let pageSize = backRoute == .overview ? overviewSize : detailSize
                    ServiceDetailContent(runtime: runtime, initialFilter: filter, onBack: goBack)
                        .id("\(id)-\(filter)")
                        .frame(width: pageSize.width, height: pageSize.height)
                } else {
                    listPage(opener: opener).frame(width: listSize.width)
                }
            case .editor(let target):
                ServiceEditorView(target: target, onClose: goBack)
                    .id(target)
                    .frame(width: detailSize.width, height: detailSize.height)
            }
        }
        .environment(\.editInPanel) { target in go(to: .editor(target)) }
        .overlay(alignment: .bottomTrailing) {
            let target = resizeTarget
            PanelResizeGrip(current: target.current, limits: Self.limits) { size in
                target.width.wrappedValue = size.width
                target.height.wrappedValue = size.height
            } onReset: {
                target.width.wrappedValue = 0
                target.height.wrappedValue = 0
            }
        }
        .background(Theme.background)
        .background(KeepOnScreen())
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
                .frame(maxHeight: listSize.height)
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
            Button { go(to: .editor(.new)) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Add service")
            Menu {
                Button("Add Service…") { go(to: .editor(.new)) }
                Button("Startup Order…") { go(to: .startupOrder) }
                Button("All Services Monitor") { go(to: .overview) }
                Button("Clear All Error Counts", action: model.clearAllErrorCounts)
                    .disabled(!model.hasErrorCounts)
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
            Button("Add Service…") { go(to: .editor(.new)) }
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
    @Environment(\.editInPanel) private var editInPanel
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
            Button("Clear Error Count", action: runtime.clearErrorCount)
                .disabled(runtime.logs.errorCount == 0 && runtime.logs.warnCount == 0)
            Button("Edit…") { (editInPanel ?? opener.editor)(.edit(runtime.id)) }
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

/// Bottom-right corner of the panel: drag to resize the current page, double-click for the default size.
private struct PanelResizeGrip: View {
    let current: CGSize
    let limits: PanelSizing.Limits
    let onResize: (CGSize) -> Void
    let onReset: () -> Void
    @State private var startSize: CGSize?

    var body: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.secondaryText.opacity(0.7))
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
            .padding(2)
            .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startSize ?? current
                        startSize = start
                        let size = PanelSizing.resized(width: start.width, height: start.height,
                                                       dx: drag.translation.width, dy: drag.translation.height,
                                                       limits: limits)
                        onResize(CGSize(width: size.width, height: size.height))
                    }
                    .onEnded { _ in startSize = nil }
            )
            .onTapGesture(count: 2, perform: onReset)
            .help("Drag to resize · double-click for the default size")
    }
}
