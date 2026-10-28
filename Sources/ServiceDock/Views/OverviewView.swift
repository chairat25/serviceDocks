import AppKit
import ServiceDockCore
import SwiftUI

private enum OverviewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case combined = "Combined"
    var id: String { rawValue }
}

/// All Services monitor, shown as a page of the menu-bar panel.
/// Grid: one live log tile per service. Combined: status table + one interleaved log.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let onBack: () -> Void
    let onOpenService: (UUID, LevelFilter) -> Void
    @State private var mode = OverviewMode.grid
    @State private var filter = LevelFilter.all
    @State private var isAutoScrolling = true
    /// Services hidden from the grid and the combined log.
    @State private var hiddenServices: Set<UUID> = []

    private var shownRuntimes: [ServiceRuntime] {
        model.runtimes.filter { !hiddenServices.contains($0.id) }
    }

    var body: some View {
        let opener = WindowOpener(openWindow: openWindow)
        VStack(spacing: 0) {
            summaryBar
            Divider().overlay(Theme.stroke)
            switch mode {
            case .grid:
                LogGridView(runtimes: shownRuntimes, filter: filter, isAutoScrolling: isAutoScrolling, opener: opener,
                            onOpenService: onOpenService)
            case .combined:
                combined(opener: opener)
            }
        }
    }

    private func combined(opener: WindowOpener) -> some View {
        VSplitView {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(shownRuntimes) { runtime in
                        OverviewRow(runtime: runtime, opener: opener, onOpenService: onOpenService)
                        Divider().overlay(Theme.stroke)
                    }
                }
            }
            .frame(minHeight: 160, idealHeight: 280)

            LogConsole(lines: model.combinedLogs.lines.filter { !hiddenServices.contains($0.serviceID) },
                       serviceName: model.name(of:), onClear: model.clearCombinedLogs)
                .frame(minHeight: 200)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to services")
            Label("\(model.runningCount) / \(model.runtimes.count) running", systemImage: "square.stack.3d.up")
                .font(.system(size: 13, weight: .semibold))
            if model.problemCount > 0 {
                Label("\(model.problemCount) with problems", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
            }
            Spacer()
            Picker("", selection: $mode) {
                ForEach(OverviewMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            if mode == .grid {
                Picker("", selection: $filter) {
                    ForEach(LevelFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Toggle("Auto scroll", isOn: $isAutoScrolling)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
            }
            if mode == .grid {
                Button(action: model.resetTileSizes) {
                    Label("Default Size", systemImage: "square.grid.2x2")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Put every tile back to its normal size")
            }
            visibilityMenu
            FooterButton(title: "Run All", symbol: "play.fill", action: model.runAll)
            FooterButton(title: "Restart All", symbol: "arrow.clockwise", action: model.restartAll)
            FooterButton(title: "Stop All", symbol: "stop.fill", action: model.stopAll)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Choose which services appear.
    private var visibilityMenu: some View {
        Menu {
            ForEach(model.runtimes) { runtime in
                Toggle(runtime.config.name, isOn: Binding(
                    get: { !hiddenServices.contains(runtime.id) },
                    set: { isShown in
                        hiddenServices = isShown ? hiddenServices.subtracting([runtime.id]) : hiddenServices.union([runtime.id])
                    }
                ))
            }
            Divider()
            Button("Show All") { hiddenServices = [] }
        } label: {
            Label("\(shownRuntimes.count)/\(model.runtimes.count) shown", systemImage: "eye")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct OverviewRow: View {
    let runtime: ServiceRuntime
    let opener: WindowOpener
    let onOpenService: (UUID, LevelFilter) -> Void

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: runtime.status, size: 10)
            Circle().fill(Theme.serviceColor(runtime.id)).frame(width: 4, height: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(runtime.config.name).font(.system(size: 12.5, weight: .medium))
                    ErrorBadge(runtime: runtime) { onOpenService(runtime.id, .errors) }
                    CountBadge(count: runtime.logs.warnCount, color: Theme.yellow, symbol: "exclamationmark.triangle.fill")
                    EnvChangedBadge(files: runtime.changedEnvFiles, restart: runtime.restart)
                }
                Text(runtime.config.url ?? runtime.status.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(minWidth: 220, alignment: .leading)
            Spacer()
            UptimeText(startedAt: runtime.startedAt).frame(width: 120, alignment: .leading)
            Text(String(format: "CPU %.0f%%", runtime.cpu))
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 64, alignment: .trailing)
            Text(runtime.memoryKB > 0 ? ProcessStats.formatMemory(kb: runtime.memoryKB) : "—")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 64, alignment: .trailing)
            Sparkline(values: runtime.cpuHistory, color: Theme.color(for: runtime.status))
                .frame(width: 90, height: 22)
            if runtime.status.isAlive {
                Button(action: runtime.restart) { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                    .help("Restart")
            } else {
                Button(action: runtime.start) { Image(systemName: "play.fill") }.buttonStyle(.borderless)
                    .help("Run")
            }
            ServiceActionsMenu(runtime: runtime, opener: opener) { onOpenService(runtime.id, .all) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(runtime.hasProblem ? Theme.red.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenService(runtime.id, .all) }
    }
}
