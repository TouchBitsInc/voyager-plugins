import AppKit
import SwiftUI

/// The Restyle Plugin: the signed carrier of the site scripts Voyager uses to
/// rearrange sites' own chrome around its sidebar (`../AGENTS.md`). Voyager
/// reads its manifest and `Sites` scripts from the installed app, checks it's
/// TouchBits', and puts them in pages itself; the app never needs to run.
///
/// Opened anyway — from Voyager's Settings (`voyager-restyle-plugin://
/// settings`) or Finder — it says what it is and where its styles are
/// chosen, and quits with its window. Opened by any other URL, it quits.
@main
@MainActor
final class RestylePluginApp: NSObject, NSApplicationDelegate {
    private static let delegate = RestylePluginApp()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.mainMenu = menu()
        app.run()
    }

    private var window: NSWindow?
    /// Whether a URL that isn't `settings` opened it: then there's nothing
    /// to show.
    private var openedForNothing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A URL arrives just after launch; with none, it was opened from
        // Finder, and says what it is.
        DispatchQueue.main.async { [self] in
            if openedForNothing, window == nil { NSApp.terminate(nil) } else { showAbout() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.host() == "settings" }) {
            showAbout()
        } else if window == nil {
            openedForNothing = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func showAbout() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.title = "Restyle Plugin"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private static func menu() -> NSMenu {
        let menu = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "Quit Restyle Plugin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(app)
        return menu
    }
}

/// What the plugin is, and where its styles are picked.
private struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Restyle Plugin")
                .font(.title2.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Voyager uses it to rearrange sites to fit beside its sidebar. Choose a site's style from Voyager's ⋯ menu, under Styles; turn the plugin off in Voyager's Settings.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { NSApp.terminate(nil) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 340)
    }
}
