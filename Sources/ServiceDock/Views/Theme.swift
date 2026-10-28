import ServiceDockCore
import SwiftUI

enum Theme {
    static let background = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.17)
    static let console = Color(red: 0.07, green: 0.08, blue: 0.09)
    static let stroke = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.55)
    static let accent = Color(red: 0.36, green: 0.55, blue: 1.0)

    static let green = Color(red: 0.25, green: 0.80, blue: 0.45)
    static let yellow = Color(red: 0.98, green: 0.75, blue: 0.20)
    static let red = Color(red: 0.95, green: 0.33, blue: 0.33)
    static let gray = Color.white.opacity(0.35)

    static func color(for status: ServiceStatus) -> Color {
        switch status {
        case .running: green
        case .starting, .stopping: yellow
        case .down: red
        case .stopped: gray
        }
    }

    static func color(for level: LogLevel) -> Color {
        switch level {
        case .error: red
        case .warn: yellow
        case .debug: gray
        case .info: green
        }
    }

    /// Stable per-service colour for the combined log.
    static func serviceColor(_ id: UUID) -> Color {
        let palette: [Color] = [.cyan, .pink, .orange, .mint, .purple, .teal, .indigo, .yellow, .green, .blue]
        let index = id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[index % palette.count]
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct StatusDot: View {
    let status: ServiceStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Theme.color(for: status))
            .frame(width: size, height: size)
            .shadow(color: Theme.color(for: status).opacity(status == .running ? 0.7 : 0), radius: 3)
    }
}

struct StatusLabel: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: status)
            Text(status.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.color(for: status))
                .lineLimit(1)
        }
    }
}

struct StatusPill: View {
    let status: ServiceStatus

    var body: some View {
        StatusLabel(status: status)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.color(for: status).opacity(0.14), in: Capsule())
    }
}

struct IconTile: View {
    let symbol: String
    var size: CGFloat = 32
    var tint: Color = .white

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: size * 0.28))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).stroke(Theme.stroke))
    }
}

/// Small red/yellow counter, e.g. "3 errors".
struct CountBadge: View {
    let count: Int
    let color: Color
    let symbol: String

    var body: some View {
        if count > 0 {
            Label("\(count)", systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())
                .help("\(count) since last clear")
        }
    }
}

struct EnvChangedBadge: View {
    let files: [String]
    let restart: () -> Void

    var body: some View {
        if !files.isEmpty {
            Button(action: restart) {
                Label("env changed", systemImage: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.yellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.yellow.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("\(files.joined(separator: ", ")) changed after start — click to restart")
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let peak = max(values.max() ?? 1, 5)
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: CGFloat(index) * step,
                                    y: size.height - CGFloat(value / peak) * (size.height - 2) - 1)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), lineWidth: 1.4)
        }
    }
}

/// Plain toolbar-style button used in footers.
struct FooterButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func card() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke))
    }
}
