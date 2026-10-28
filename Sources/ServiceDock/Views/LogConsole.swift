import AppKit
import ServiceDockCore
import SwiftUI

enum LevelFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case problems = "Warn + Error"
    case errors = "Errors"

    var id: String { rawValue }

    func includes(_ level: LogLevel) -> Bool {
        switch self {
        case .all: true
        case .problems: level == .warn || level == .error
        case .errors: level == .error
        }
    }
}

/// Monospaced log viewer with search, level filter, auto-scroll, clear and copy.
struct LogConsole: View {
    let lines: [LogLine]
    /// When set, each line is prefixed with the service name (combined view).
    var serviceName: ((UUID) -> String)?
    let onClear: () -> Void

    @State private var isAutoScrolling = true
    @State private var isAtBottom = true
    @State private var search = ""
    @State private var levelFilter: LevelFilter

    init(lines: [LogLine], serviceName: ((UUID) -> String)? = nil, initialFilter: LevelFilter = .all,
         onClear: @escaping () -> Void) {
        self.lines = lines
        self.serviceName = serviceName
        self.onClear = onClear
        _levelFilter = State(initialValue: initialFilter)
    }

    private var visibleLines: [LogLine] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return lines.filter { line in
            levelFilter.includes(line.level) && (query.isEmpty || line.text.localizedCaseInsensitiveContains(query)
                || (serviceName?(line.serviceID).localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    var body: some View {
        let visible = visibleLines
        VStack(spacing: 0) {
            filterBar
            Divider().overlay(Theme.stroke)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { line in
                            LogRow(line: line, serviceName: serviceName?(line.serviceID)).id(line.id)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.console)
                .overlay {
                    if visible.isEmpty {
                        Text(lines.isEmpty ? "No output yet"
                             : "No lines match the filter — older errors may have scrolled out of the log.\nRight-click the red badge to clear its count.")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
                } action: { _, atBottom in
                    isAtBottom = atBottom
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    // Only a user-driven scroll toggles following: scrolled up → pause, back at bottom → resume.
                    if oldPhase != .idle, newPhase == .idle { isAutoScrolling = isAtBottom }
                }
                .onChange(of: visible.last?.id) { _, lastID in
                    guard isAutoScrolling, let lastID else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
                .onAppear {
                    if let lastID = visible.last?.id { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
            Divider().overlay(Theme.stroke)
            footer(visible: visible)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField("Filter logs", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            Picker("", selection: $levelFilter) {
                ForEach(LevelFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func footer(visible: [LogLine]) -> some View {
        HStack {
            Toggle("Auto scroll", isOn: $isAutoScrolling)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
            Text("\(visible.count) lines")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            FooterButton(title: "Clear", symbol: "trash", action: onClear)
            FooterButton(title: "Copy", symbol: "doc.on.doc") { copy(visible) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func copy(_ lines: [LogLine]) {
        let text = lines.map { line in
            let prefix = serviceName.map { "[\($0(line.serviceID))] " } ?? ""
            return "\(Theme.timeFormatter.string(from: line.date)) [\(line.level.rawValue.uppercased())] \(prefix)\(line.text)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct LogRow: View {
    let line: LogLine
    let serviceName: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Theme.timeFormatter.string(from: line.date))
                .foregroundStyle(Theme.secondaryText)
            Text("[\(line.level.rawValue.uppercased())]")
                .foregroundStyle(Theme.color(for: line.level))
                .frame(width: 58, alignment: .leading)
            if let serviceName {
                Text(serviceName)
                    .foregroundStyle(Theme.serviceColor(line.serviceID))
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
            }
            Text(line.text)
                .foregroundStyle(line.level == .error ? Theme.red : .white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }
}
