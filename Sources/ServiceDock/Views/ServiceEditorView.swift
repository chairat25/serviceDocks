import AppKit
import ServiceDockCore
import SwiftUI

/// Add or edit a service.
struct ServiceEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: EditorTarget
    /// Set when shown as a page of the menu-bar panel: closes the page instead of the window.
    var onClose: (() -> Void)?

    @State private var draft = ServiceConfig(name: "", path: "", command: "yarn start:dev")
    @State private var isIconPicked = false
    @State private var errors: [ServiceConfig.ValidationError] = []
    @State private var didLoad = false
    @State private var portsText = ""

    private var isNew: Bool { target == .new }

    var body: some View {
        VStack(spacing: 0) {
            if let onClose { pageHeader(onClose: onClose) }
            form
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .navigationTitle(isNew ? "Add Service" : "Edit Service")
        .onAppear(perform: load)
    }

    private func pageHeader(onClose: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")
            Text(isNew ? "Add Service" : "Edit \(draft.name)").font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.stroke) }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("auth-service"))
                    .onChange(of: draft.name) { _, name in
                        if !isIconPicked { draft.icon = ServiceConfig.suggestedIcon(for: name) }
                    }
                HStack {
                    TextField("Folder", text: $draft.path, prompt: Text("~/projects/genie/services/auth"))
                    Button("Choose…", action: chooseFolder)
                }
                HStack {
                    TextField("Command", text: $draft.command, prompt: Text("yarn start:dev"))
                        .font(.system(.body, design: .monospaced))
                    CommandPresetMenu(command: $draft.command)
                }
            }
            Section {
                TextField("URL (optional)", text: optionalBinding(\.url), prompt: Text("http://localhost:3001"))
                TextField("Ready pattern (optional regex)", text: optionalBinding(\.readyPattern),
                          prompt: Text("leave empty for built-in detection"))
                Toggle("Stop leftover processes on its ports before starting", isOn: $draft.freesPortsOnStart)
                if draft.freesPortsOnStart {
                    TextField("Extra ports to free (optional)", text: $portsText, prompt: Text("e.g. 8000, 50055"))
                    if !draft.learnedPorts.isEmpty {
                        Text("Detected automatically: \(PortList.format(draft.learnedPorts))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                iconPicker
            }
            if !errors.isEmpty {
                Section {
                    ForEach(errors.map(\.message), id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) { buttons }
        .frame(width: onClose == nil ? 520 : nil)
        .fixedSize(horizontal: false, vertical: onClose == nil)
    }

    private var iconPicker: some View {
        LabeledContent("Icon") {
            HStack(spacing: 4) {
                ForEach(ServiceConfig.iconChoices, id: \.self) { symbol in
                    Button {
                        draft.icon = symbol
                        isIconPicked = true
                    } label: {
                        Image(systemName: symbol)
                            .frame(width: 24, height: 24)
                            .background(draft.icon == symbol ? Theme.accent.opacity(0.35) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
            Button(isNew ? "Add" : "Save", action: save)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    /// Binds an optional String field, storing empty text as `nil`.
    private func optionalBinding(_ keyPath: WritableKeyPath<ServiceConfig, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        )
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if case .edit(let id) = target, let runtime = model.runtime(for: id) {
            draft = runtime.config
            portsText = PortList.format(runtime.config.ports)
            isIconPicked = true
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.path = ServiceConfig.abbreviate(url.path, home: NSHomeDirectory())
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { draft.name = url.lastPathComponent }
    }

    private func save() {
        var withPorts = draft
        withPorts.ports = PortList.parse(portsText)
        let cleaned = trimmed(withPorts)
        errors = cleaned.validate(home: NSHomeDirectory()) { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        guard errors.isEmpty else { return }
        isNew ? model.add(cleaned) : model.update(cleaned)
        close()
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func trimmed(_ config: ServiceConfig) -> ServiceConfig {
        var copy = config
        copy.name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.path = config.path.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.command = config.command.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.url = config.url?.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

/// Pick a saved command (or one another service uses), save the current one, or remove a preset.
private struct CommandPresetMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var command: String

    private var usedElsewhere: [String] {
        CommandPresets.usedElsewhere(serviceCommands: model.runtimes.map(\.config.command),
                                     presets: model.commandPresets)
    }

    var body: some View {
        Menu {
            if !model.commandPresets.isEmpty {
                Section("Presets") {
                    ForEach(model.commandPresets, id: \.self) { preset in
                        Button(preset) { command = preset }
                    }
                }
            }
            if !usedElsewhere.isEmpty {
                Section("Used by other services") {
                    ForEach(usedElsewhere, id: \.self) { used in
                        Button(used) { command = used }
                    }
                }
            }
            Divider()
            Button("Add “\(command.trimmingCharacters(in: .whitespaces))” as Preset") {
                model.addCommandPreset(command)
            }
            .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty
                      || model.commandPresets.contains(command.trimmingCharacters(in: .whitespaces)))
            if !model.commandPresets.isEmpty {
                Menu("Remove Preset") {
                    ForEach(model.commandPresets, id: \.self) { preset in
                        Button(preset) { model.removeCommandPreset(preset) }
                    }
                }
            }
        } label: {
            Label("Presets", systemImage: "text.badge.plus")
        }
        .fixedSize()
        .help("Command presets")
    }
}
