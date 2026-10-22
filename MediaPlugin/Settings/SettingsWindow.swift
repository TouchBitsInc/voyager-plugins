import AppKit
import SwiftUI

/// The plugin's window — all it shows when opened on its own: where saved
/// videos go, and the tools it runs. Turning the plugin on or off is
/// Voyager's, in its Settings.
enum SettingsWindow {
    @MainActor
    static func make() -> NSWindow {
        let view = SettingsView(settings: PluginSettings.shared, tool: VideoPlugins.shared)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = String(localized: "Media Plugin")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        return window
    }
}

private struct SettingsView: View {
    @Bindable var settings: PluginSettings
    let tool: VideoPlugins

    var body: some View {
        Form {
            Section {
                LabeledContent("Save Videos To") {
                    HStack {
                        Text(FileManager.default.displayName(atPath: settings.downloadFolder.path))
                            .foregroundStyle(.secondary)
                        Button("Choose\u{2026}", action: chooseFolder)
                    }
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("Right-click a playing video and choose Download Video.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                ToolRow(tool: tool)
            } header: {
                Text("Tools")
            } footer: {
                Text("Command-line tools the plugin runs, each a version its release brings: a new version comes with a plugin update.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 350)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.downloadFolder
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        settings.downloadFolder = folder
    }
}

/// One tool: what it is, and the version the plugin brings.
private struct ToolRow: View {
    let tool: VideoPlugins

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tool.name).font(.headline)
                    Link(destination: tool.homepage) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Open \(tool.name)\u{2019}s project page")
                }
                Text(tool.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                status.font(.caption)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var status: some View {
        if let version = tool.version, tool.isInstalled {
            Text("Version \(version) \u{00B7} Comes with the plugin").foregroundStyle(.secondary)
        } else {
            Text("Missing from this build").foregroundStyle(.red)
        }
    }
}
