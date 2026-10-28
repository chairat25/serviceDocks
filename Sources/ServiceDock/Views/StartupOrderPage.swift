import ServiceDockCore
import SwiftUI

/// Lets the user decide which services start first by typing a number per service.
struct StartupOrderPage: View {
    @Environment(AppModel.self) private var model
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    explanation
                    VStack(spacing: 0) {
                        ForEach(model.runtimes) { runtime in
                            OrderRow(runtime: runtime)
                            if runtime.id != model.runtimes.last?.id { Divider().overlay(Theme.stroke) }
                        }
                    }
                    .card()
                    summary
                }
                .padding(14)
            }
            Divider().overlay(Theme.stroke)
            timeoutRow
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to services")
            IconTile(symbol: "list.number", size: 30, tint: Theme.accent)
            Text("Startup Order").font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var explanation: some View {
        Text("ใส่เลขลำดับให้แต่ละ service — เลขน้อยเริ่มก่อน, เลขเท่ากันเริ่มพร้อมกัน. "
             + "ลำดับถัดไปจะเริ่มเมื่อทุกตัวในลำดับก่อนหน้าพร้อมแล้ว (เจอ log เช่น “compiled successfully”).")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText)
    }

    /// "1 → master-data   2 → authentication, profile …"
    private var summary: some View {
        let steps = StartPlan.stages(model.runtimes.map { (id: $0.id, stage: $0.config.startStage) })
        return VStack(alignment: .leading, spacing: 6) {
            Text("Run All จะเริ่มตามนี้").font(.system(size: 12, weight: .semibold))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, ids in
                let names = ids.map(model.name(of:)).joined(separator: ", ")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Theme.accent.opacity(0.25), in: Circle())
                    Text(names).font(.system(size: 12))
                    if index > 0 { Text("(รอลำดับก่อนหน้าพร้อม)").font(.system(size: 11)).foregroundStyle(Theme.secondaryText) }
                }
            }
        }
    }

    private var timeoutRow: some View {
        HStack(spacing: 6) {
            Text("รอแต่ละลำดับพร้อมนานสุด").font(.system(size: 12))
            NumberField(value: model.stageTimeoutSeconds, range: AppConfig.stageTimeoutRange) { model.setStageTimeout($0) }
            Text("วินาที แล้วไปต่อเลย").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct OrderRow: View {
    @Environment(AppModel.self) private var model
    let runtime: ServiceRuntime

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: runtime.config.icon, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(runtime.config.name).font(.system(size: 12.5, weight: .medium))
                Text(runtime.config.command).font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer()
            Text("ลำดับ").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            NumberField(value: runtime.config.startStage, range: StartPlan.stageRange) { model.setStage($0, for: runtime.id) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Small numeric text field. Commits on Return or focus loss; invalid text snaps back to the current value.
private struct NumberField: View {
    let value: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: 56)
            .focused($isFocused)
            .onAppear { text = String(value) }
            .onChange(of: value) { _, new in if !isFocused { text = String(new) } }
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            .onSubmit(commit)
    }

    private func commit() {
        guard let number = Int(text.trimmingCharacters(in: .whitespaces)) else {
            text = String(value)
            return
        }
        let clamped = min(max(number, range.lowerBound), range.upperBound)
        text = String(clamped)
        if clamped != value { onCommit(clamped) }
    }
}

/// Banner above the footer while / after a staged start.
struct StartupBanner: View {
    let state: StartupState
    let onCancel: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if state.isActive {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.yellow)
            }
            VStack(alignment: .leading, spacing: 2) {
                if state.isActive {
                    Text("Starting stage \(state.stage) of \(state.totalStages)")
                        .font(.system(size: 12, weight: .medium))
                    Text("Waiting for \(state.waitingFor.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(state.notes, id: \.self) { note in
                    Text(note).font(.system(size: 11)).foregroundStyle(Theme.yellow)
                }
            }
            Spacer()
            if state.isActive {
                Button("Cancel", action: onCancel).controlSize(.small)
            } else {
                Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.yellow.opacity(0.08))
    }
}
