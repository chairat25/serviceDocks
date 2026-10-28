import AppKit
import ServiceDockCore
import SwiftUI

/// Mini monitor for one service: Logs / Info / Actions.
struct ServiceDetailView: View {
    @Environment(AppModel.self) private var model
    let serviceID: UUID

    var body: some View {
        Group {
            if let runtime = model.runtime(for: serviceID) {
                ServiceDetailContent(runtime: runtime)
            } else {
                ContentUnavailableView("Service removed", systemImage: "trash")
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case logs = "Logs", info = "Info", actions = "Actions"
    var id: String { rawValue }
}

/// Detail page, used both as its own window and as a page inside the menu-bar panel.
struct ServiceDetailContent: View {
    @Environment(\.openWindow) private var openWindow
    let runtime: ServiceRuntime
    var initialFilter = LevelFilter.all
    /// Set when shown inside the panel: draws a back button and replaces closing the window.
    var onBack: (() -> Void)?
    @State private var tab = DetailTab.logs

    var body: some View {
        let opener = WindowOpener(openWindow: openWindow)
        VStack(spacing: 0) {
            header(opener: opener)
            Picker("", selection: $tab) {
                ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .padding(.bottom, 10)
            Divider().overlay(Theme.stroke)
            switch tab {
            case .logs:
                LogConsole(lines: runtime.logs.lines, initialFilter: initialFilter, onClear: runtime.clearLogs)
            case .info:
                ServiceInfoTab(runtime: runtime)
            case .actions:
                ServiceActionsTab(runtime: runtime, opener: opener, onRemoved: onBack)
            }
        }
        .navigationTitle(runtime.config.name)
    }

    private func header(opener: WindowOpener) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        .frame(width: 24, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Back to services")
            }
            IconTile(symbol: runtime.config.icon, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(runtime.config.name).font(.system(size: 17, weight: .semibold))
                    if let url = runtime.config.url.flatMap(URL.init(string:)) {
                        Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                            .buttonStyle(.borderless)
                            .help(url.absoluteString)
                    }
                    EnvChangedBadge(files: runtime.changedEnvFiles, restart: runtime.restart)
                }
                Text(runtime.displayPath).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                Text(runtime.config.command).font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 14) {
                    StatusPill(status: runtime.status)
                    UptimeText(startedAt: runtime.startedAt)
                    CountBadge(count: runtime.logs.errorCount, color: Theme.red, symbol: "xmark.octagon.fill")
                        .help("Lines detected as ERROR since the last clear")
                    CountBadge(count: runtime.logs.warnCount, color: Theme.yellow, symbol: "exclamationmark.triangle.fill")
                }
                .padding(.top, 4)
            }
            Spacer()
            HStack(spacing: 6) {
                if runtime.status.isAlive {
                    Button("Restart", systemImage: "arrow.clockwise", action: runtime.restart)
                    Button("Stop", systemImage: "stop.fill", action: runtime.stop)
                } else {
                    Button("Run", systemImage: "play.fill", action: runtime.start)
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
        }
        .padding(16)
    }
}

struct UptimeText: View {
    let startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Text("Uptime").foregroundStyle(Theme.secondaryText)
                Text(startedAt.map { DurationFormat.clock(context.date.timeIntervalSince($0)) } ?? "—")
                    .monospacedDigit()
            }
            .font(.system(size: 12))
        }
    }
}

private struct ServiceInfoTab: View {
    let runtime: ServiceRuntime

    var body: some View {
        Form {
            LabeledContent("Folder", value: runtime.directory)
            LabeledContent("Command", value: runtime.config.command)
            LabeledContent("URL", value: runtime.config.url ?? "—")
            LabeledContent("Ready pattern", value: runtime.config.readyPattern ?? "built-in")
            LabeledContent("Ports freed before start",
                           value: runtime.config.portsToFree.isEmpty ? (runtime.config.freesPortsOnStart ? "none known yet" : "off")
                               : PortList.format(runtime.config.portsToFree))
            LabeledContent("Status", value: runtime.status.label)
            LabeledContent("CPU", value: String(format: "%.1f %%", runtime.cpu))
            LabeledContent("Memory", value: ProcessStats.formatMemory(kb: runtime.memoryKB))
            LabeledContent("Errors / warnings", value: "\(runtime.logs.errorCount) / \(runtime.logs.warnCount)")
            LabeledContent("Env files changed since start",
                           value: runtime.changedEnvFiles.isEmpty ? "none" : runtime.changedEnvFiles.joined(separator: ", "))
            LabeledContent("CPU history") {
                Sparkline(values: runtime.cpuHistory, color: Theme.green).frame(width: 180, height: 28)
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .scrollContentBackground(.hidden)
    }
}

private struct ServiceActionsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editInPanel) private var editInPanel
    let runtime: ServiceRuntime
    let opener: WindowOpener
    let onRemoved: (() -> Void)?
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section("Process") {
                Button("Run", systemImage: "play.fill", action: runtime.start).disabled(runtime.status.isAlive)
                Button("Restart (reload .env)", systemImage: "arrow.clockwise", action: runtime.restart)
                Button("Stop", systemImage: "stop.fill", action: runtime.stop).disabled(!runtime.status.isAlive)
            }
            Section("Open") {
                Button("Open Folder in Finder", systemImage: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: runtime.directory))
                }
                Button("Open in Terminal", systemImage: "terminal") {
                    NSWorkspace.shared.open([URL(fileURLWithPath: runtime.directory)],
                                            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                            configuration: NSWorkspace.OpenConfiguration())
                }
                if let url = runtime.config.url.flatMap(URL.init(string:)) {
                    Button("Open \(url.absoluteString)", systemImage: "safari") { NSWorkspace.shared.open(url) }
                }
            }
            Section("Service") {
                Button("Edit…", systemImage: "pencil") { (editInPanel ?? opener.editor)(.edit(runtime.id)) }
                Button("Remove Service", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .confirmationDialog("Remove \(runtime.config.name)?", isPresented: $isConfirmingDelete) {
            Button("Stop and Remove", role: .destructive) {
                model.remove(id: runtime.id)
                if let onRemoved { onRemoved() } else { dismiss() }
            }
        } message: {
            Text("The process is stopped. Your project folder is not touched.")
        }
    }
}
