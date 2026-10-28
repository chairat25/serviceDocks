import ServiceDockCore
import SwiftUI

/// Red error counter. Hover previews the latest error lines; click opens the log filtered to errors.
struct ErrorBadge: View {
    private static let previewLimit = 5
    private static let hoverDelay: Duration = .milliseconds(250)

    let runtime: ServiceRuntime
    let onOpen: () -> Void

    @State private var isPreviewShown = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        if runtime.logs.errorCount > 0 {
            Button(action: onOpen) {
                CountBadge(count: runtime.logs.errorCount, color: Theme.red, symbol: "xmark.octagon.fill")
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Clear Error Count") { runtime.clearErrorCount() }
            }
            .onHover(perform: hoverChanged)
            .popover(isPresented: $isPreviewShown, arrowEdge: .bottom) {
                ErrorPreview(runtime: runtime, lines: runtime.recentErrors(limit: Self.previewLimit))
            }
        }
    }

    private func hoverChanged(_ isHovering: Bool) {
        hoverTask?.cancel()
        guard isHovering else {
            isPreviewShown = false
            return
        }
        hoverTask = Task {
            try? await Task.sleep(for: Self.hoverDelay)
            if !Task.isCancelled { isPreviewShown = true }
        }
    }
}

private struct ErrorPreview: View {
    let runtime: ServiceRuntime
    let lines: [LogLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(runtime.logs.errorCount) error lines in \(runtime.config.name)")
                .font(.system(size: 12, weight: .semibold))
            Text("Lines detected as ERROR since the last clear. The service may still be running fine.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Divider()
            if lines.isEmpty {
                Text("Older errors already scrolled out of the log buffer.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Theme.timeFormatter.string(from: line.date)).foregroundStyle(Theme.secondaryText)
                    Text(line.text).foregroundStyle(Theme.red).lineLimit(3)
                }
                .font(.system(size: 11, design: .monospaced))
            }
            Divider()
            Text("Click the badge to open the log filtered to errors · right-click to clear the count.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .frame(width: 460, alignment: .leading)
    }
}
