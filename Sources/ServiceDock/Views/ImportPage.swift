import AppKit
import ServiceDockCore
import SwiftUI

/// A config file picked with Import Config…, waiting for Merge or Replace.
struct ImportDraft: Equatable {
    let fileName: String
    let config: AppConfig
}

/// Shows what an imported config contains, lets the user move its folders to a new root, then merges or replaces.
struct ImportPage: View {
    @Environment(AppModel.self) private var model
    let draft: ImportDraft
    let onDone: () -> Void

    /// Folder chosen with Choose New Root…; `nil` keeps the paths from the file.
    @State private var newRoot: String?

    private var home: String { NSHomeDirectory() }
    private var oldRoot: String? { ConfigTransfer.commonRoot(of: draft.config.services.map(\.path)) }

    private var config: AppConfig {
        guard let oldRoot, let newRoot else { return draft.config }
        return ConfigTransfer.remapping(draft.config, from: oldRoot, to: newRoot, home: home)
    }

    private var missingCount: Int { config.services.count { !folderExists($0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    if oldRoot != nil { rootRow }
                    if !config.services.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(config.services) { service in
                                ImportRow(service: service, exists: folderExists(service), isUpdate: isUpdate(service))
                                if service.id != config.services.last?.id { Divider().overlay(Theme.stroke) }
                            }
                        }
                        .card()
                    }
                }
                .padding(14)
            }
            Divider().overlay(Theme.stroke)
            buttons
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onDone) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back without importing")
            IconTile(symbol: "square.and.arrow.down", size: 30, tint: Theme.accent)
            Text("Import \(draft.fileName)").font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(config.services.count) services, \(config.commandPresets.count) command presets")
                .font(.system(size: 12.5, weight: .medium))
            Text(missingCount == 0
                 ? "All folders found on this Mac."
                 : "\(missingCount) folder(s) not found on this Mac — choose the new root folder, or fix them later in Edit Service.")
                .font(.system(size: 11.5))
                .foregroundStyle(missingCount == 0 ? Theme.secondaryText : Theme.yellow)
        }
    }

    private var rootRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Root folder").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                Text(newRoot.map { ServiceConfig.abbreviate($0, home: home) } ?? oldRoot ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if newRoot != nil { Button("Undo") { newRoot = nil } }
            Button("Choose New Root…", action: chooseRoot)
        }
        .padding(10)
        .card()
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onDone).keyboardShortcut(.cancelAction)
            Button("Replace All") { finish(.replace) }
                .help("Use only the services in this file. Services not in it are stopped and removed.")
            Button("Merge") { finish(.merge) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .help("Add new services and update the ones with the same name.")
        }
        .disabled(config.services.isEmpty)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that replaces \(oldRoot ?? "the old root") on this Mac"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        newRoot = url.path
    }

    private func finish(_ mode: AppModel.ImportMode) {
        model.applyImport(config, mode: mode)
        onDone()
    }

    private func folderExists(_ service: ServiceConfig) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: service.expandedPath(home: home), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func isUpdate(_ service: ServiceConfig) -> Bool {
        model.runtimes.contains { ConfigTransfer.sameName($0.config.name, service.name) }
    }
}

private struct ImportRow: View {
    let service: ServiceConfig
    let exists: Bool
    /// A local service with the same name will be updated (Merge) instead of added.
    let isUpdate: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: service.icon, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(service.name).font(.system(size: 12.5, weight: .medium))
                    Text(isUpdate ? "update" : "new")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.stroke, in: Capsule())
                }
                Text(service.path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(exists ? Theme.green : Theme.red)
                .help(exists ? "Folder found" : "Folder not found on this Mac")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
