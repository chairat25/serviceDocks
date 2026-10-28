import AppKit
import ServiceDockCore
import SwiftUI

/// One tile per service, each with its own live log. Columns and tile height adapt to the
/// number of services and the window size. Tiles can be dragged by their header to reorder and
/// resized from the bottom-right corner (width snaps to whole columns).
struct LogGridView: View {
    private static let spacing: CGFloat = 10
    private static let padding: CGFloat = 12
    private static let minTileWidth: CGFloat = 380
    private static let minTileHeight: CGFloat = 200
    /// Smallest height a tile can be resized to.
    private static let minResizedHeight: CGFloat = 140

    @Environment(AppModel.self) private var model
    let runtimes: [ServiceRuntime]
    let filter: LevelFilter
    let isAutoScrolling: Bool
    let opener: WindowOpener
    let onOpenService: (UUID, LevelFilter) -> Void
    /// Size shown while a resize grip is being dragged; saved on release.
    @State private var resizing: (id: UUID, spec: TileSpec)?
    @State private var dropTarget: UUID?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - Self.padding * 2
            let columns = TileGrid.columns(count: runtimes.count, width: width, minTileWidth: Self.minTileWidth)
            let rows = TileGrid.rows(count: runtimes.count, columns: columns)
            let autoHeight = TileGrid.tileHeight(available: proxy.size.height - Self.padding * 2, rows: rows,
                                                 spacing: Self.spacing, minHeight: Self.minTileHeight)
            let layout = TilePacking.layout(tiles: runtimes.map(spec(of:)), columns: columns, width: width,
                                            spacing: Self.spacing, autoHeight: autoHeight)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(zip(runtimes, layout.frames)), id: \.0.id) { runtime, frame in
                        tile(runtime, frame: frame, columns: columns, width: width)
                    }
                }
                .frame(width: max(width, 0), height: layout.totalHeight, alignment: .topLeading)
                .animation(.snappy(duration: 0.25), value: runtimes.map(\.id))
                .padding(Self.padding)
            }
        }
        .overlay {
            if runtimes.isEmpty {
                Text("No services to show").foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func spec(of runtime: ServiceRuntime) -> TileSpec {
        if let resizing, resizing.id == runtime.id { return resizing.spec }
        return TileSpec(span: runtime.config.tileSpan, height: runtime.config.tileHeight)
    }

    private func tile(_ runtime: ServiceRuntime, frame: TileFrame, columns: Int, width: CGFloat) -> some View {
        ServiceTile(runtime: runtime, filter: filter, isAutoScrolling: isAutoScrolling, opener: opener,
                    isDropTarget: dropTarget == runtime.id, onOpenService: onOpenService)
            .overlay {
                ResizeHandles(
                    onChange: { edge, translation in
                        let size = edge.resized(width: frame.width, height: frame.height,
                                                dx: translation.width, dy: translation.height)
                        let span = TilePacking.span(forWidth: size.width, columns: columns, width: width,
                                                    spacing: Self.spacing)
                        resizing = (runtime.id, TileSpec(span: span, height: max(Self.minResizedHeight, size.height)))
                    },
                    onEnd: {
                        guard let resizing, resizing.id == runtime.id else { return }
                        model.setTileSize(id: runtime.id, span: resizing.spec.span, height: resizing.spec.height)
                        self.resizing = nil
                    },
                    onReset: { model.setTileSize(id: runtime.id, span: nil, height: nil) }
                )
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.x, y: frame.y)
            .dropDestination(for: String.self) { items, _ in
                dropTarget = nil
                guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                let ids = runtimes.map(\.id)
                let isMovingForward = (ids.firstIndex(of: dragged) ?? 0) < (ids.firstIndex(of: runtime.id) ?? 0)
                model.move(id: dragged, onto: runtime.id, after: isMovingForward)
                return true
            } isTargeted: { isTargeted in
                if isTargeted { dropTarget = runtime.id } else if dropTarget == runtime.id { dropTarget = nil }
            }
    }
}

/// Invisible strips on all four edges plus a corner grip. Drag to resize (width snaps to columns),
/// double-click to go back to automatic.
private struct ResizeHandles: View {
    private static let thickness: CGFloat = 6

    let onChange: (TileEdge, CGSize) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void

    var body: some View {
        ZStack {
            VStack { strip(.top, cursor: .resizeUpDown); Spacer(); strip(.bottom, cursor: .resizeUpDown) }
            HStack { strip(.left, cursor: .resizeLeftRight); Spacer(); strip(.right, cursor: .resizeLeftRight) }
        }
        .overlay(alignment: .bottomTrailing) { corner }
    }

    private func strip(_ edge: TileEdge, cursor: NSCursor) -> some View {
        let isHorizontal = edge == .top || edge == .bottom
        return Color.clear
            .frame(width: isHorizontal ? nil : Self.thickness, height: isHorizontal ? Self.thickness : nil)
            .padding(isHorizontal ? .horizontal : .vertical, 14)
            .contentShape(Rectangle())
            .onHover { inside in if inside { cursor.push() } else { NSCursor.pop() } }
            .gesture(drag(edge))
            .onTapGesture(count: 2, perform: onReset)
    }

    private var corner: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 18, height: 18)
            .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
            .padding(4)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
            .gesture(drag(.bottomRight))
            .onTapGesture(count: 2, perform: onReset)
            .help("Drag edges or corner to resize · double-click to reset")
    }

    private func drag(_ edge: TileEdge) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { onChange(edge, $0.translation) }
            .onEnded { _ in onEnd() }
    }
}

private struct ServiceTile: View {
    private static let visibleLines = 200

    let runtime: ServiceRuntime
    let filter: LevelFilter
    let isAutoScrolling: Bool
    let opener: WindowOpener
    let isDropTarget: Bool
    let onOpenService: (UUID, LevelFilter) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            log
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isDropTarget ? Color.accentColor : borderColor, lineWidth: isDropTarget ? 2 : (runtime.hasProblem ? 1.2 : 1)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var borderColor: Color {
        if case .down = runtime.status { return Theme.red.opacity(0.7) }
        return runtime.logs.errorCount > 0 ? Theme.red.opacity(0.35) : Theme.stroke
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatusDot(status: runtime.status, size: 9)
                Text(runtime.config.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                ErrorBadge(runtime: runtime) { onOpenService(runtime.id, .errors) }
                CountBadge(count: runtime.logs.warnCount, color: Theme.yellow, symbol: "exclamationmark.triangle.fill")
                EnvChangedBadge(files: runtime.changedEnvFiles, restart: runtime.restart)
                Spacer(minLength: 4)
                if runtime.status.isAlive {
                    Button(action: runtime.restart) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Restart")
                } else {
                    Button(action: runtime.start) { Image(systemName: "play.fill") }
                        .buttonStyle(.borderless).help("Run")
                }
                ServiceActionsMenu(runtime: runtime, opener: opener) { onOpenService(runtime.id, .all) }
            }
            HStack(spacing: 10) {
                Text(runtime.status.label)
                    .foregroundStyle(Theme.color(for: runtime.status))
                UptimeText(startedAt: runtime.startedAt)
                Text(String(format: "CPU %.0f%%", runtime.cpu)).monospacedDigit()
                Text(runtime.memoryKB > 0 ? ProcessStats.formatMemory(kb: runtime.memoryKB) : "—").monospacedDigit()
                Spacer(minLength: 0)
                Sparkline(values: runtime.cpuHistory, color: Theme.color(for: runtime.status))
                    .frame(width: 60, height: 14)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenService(runtime.id, .all) }
        .draggable(runtime.id.uuidString) {
            Label(runtime.config.name, systemImage: runtime.config.icon)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        }
        .help("Drag to reorder")
    }

    private var log: some View {
        let lines = runtime.logs.lines.suffix(Self.visibleLines).filter { filter.includes($0.level) }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        LogRow(line: line, serviceName: nil).id(line.id)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.console)
            .overlay {
                if lines.isEmpty {
                    Text(runtime.logs.lines.isEmpty ? "No output yet" : "No lines match the filter")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .onChange(of: lines.last?.id) { _, lastID in
                guard isAutoScrolling, let lastID else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
            .onAppear {
                if let lastID = lines.last?.id { proxy.scrollTo(lastID, anchor: .bottom) }
            }
        }
    }
}
