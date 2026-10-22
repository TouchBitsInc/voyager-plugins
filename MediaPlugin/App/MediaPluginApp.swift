import AppKit
import Sparkle

/// The Media Plugin: plays and saves the videos Voyager hands it — and shows
/// its photos, a post's together — in windows
/// of its own, with yt-dlp — what a sandboxed App Store app can't do. An app
/// without a Dock icon, started by Voyager when a video is clicked and gone
/// once nothing's playing or saving. Started any other way — from Finder,
/// say — it shows nothing; its settings — where saved
/// videos go, and the yt-dlp it brings — open from Voyager's Settings.
///
/// Voyager's side of it is `PluginProtocol`: a request comes as
/// `voyager-media-plugin://trigger?id=…`, its file in the shared folder; the
/// answer goes back as events — `accepted`, `unhandled` when there's nothing
/// to play, so the page plays it as it would have, and `closed` with the
/// time the player stopped at, for the page to carry on from.
@main
@MainActor
final class MediaPluginApp: NSObject, NSApplicationDelegate {
    private static let delegate = MediaPluginApp()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.mainMenu = menu()
        app.run()
    }

    private let id = MediaSites.manifest?.id ?? "com.touchbits.voyager.media-plugin"
    /// Sparkle: a new plugin — a new yt-dlp in it — found at launch,
    /// downloaded meanwhile, and installed as the plugin quits.
    let updates = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var settings: NSWindow?
    private var quitting: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only with a key to check updates against: a build without one
        // doesn't update, rather than say it can't.
        if let key = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String, !key.isEmpty {
            try? updates.updater.start()
        }
        post(.ready)
        Downloads.shared.onIdle = { [weak self] in self?.quitIfIdle() }
        // Nothing to show until it's asked: gone again if nothing is.
        quitIfIdle()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == MediaSites.manifest?.scheme {
            switch url.host() {
            case "trigger":
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
                if let id { trigger(id) }
            case "settings":
                showSettings()
            default:
                quitIfIdle()
            }
        }
    }

    // MARK: - Requests

    private func trigger(_ requestID: String) {
        guard let file = PluginProtocol.requestFile(requestID),
              let data = try? Data(contentsOf: file),
              let request = try? JSONDecoder().decode(PluginRequest.self, from: data)
        else { return post(.unhandled, request: requestID) }
        // Read once: it has the site's cookies in it.
        try? FileManager.default.removeItem(at: file)

        let frame = request.frame.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) } ?? .zero
        // Photos: shown together, from the one clicked.
        if let images = request.images, !images.isEmpty {
            post(.accepted, request: requestID)
            quitting?.cancel()
            ImageViewer.show(
                ImageViewer.Request(images: images, index: request.index ?? 0, referrer: request.referrer.flatMap(URL.init(string:))),
                sourceFrame: frame,
                onClose: { [weak self] in
                    self?.post(.closed, request: requestID)
                    self?.quitIfIdle()
                }
            )
            return
        }

        let video: MediaSites.Video
        if let page = request.page.flatMap(URL.init(string:)) {
            video = .page(page)
        } else if let file = request.file.flatMap(URL.init(string:)) {
            video = .file(file, referrer: request.referrer.flatMap(URL.init(string:)))
        } else {
            return post(.unhandled, request: requestID)
        }
        // A page needs yt-dlp: without it, the page keeps its video, and
        // the settings show where to get it.
        if case .page = video, !VideoPlugins.shared.isInstalled {
            post(.unhandled, request: requestID)
            return showSettings()
        }

        post(.accepted, request: requestID)
        quitting?.cancel()
        MediaViewer.show(
            MediaViewer.Request(
                video: video,
                size: CGSize(width: request.width, height: request.height),
                startTime: request.time,
                rect: .zero
            ),
            cookies: request.cookies.compactMap(\.httpCookie),
            sourceFrame: frame,
            onUnhandled: { [weak self] in
                self?.handBack(requestID, to: request.requester)
            },
            onClose: { [weak self] time in
                self?.post(.closed, request: requestID, time: time)
                self?.quitIfIdle()
            }
        )
    }

    /// Nothing to do with the request: Voyager gets it back — and focus
    /// with it, so typing goes to its panel again rather than to a plugin
    /// with no window up.
    private func handBack(_ requestID: String, to requester: String?) {
        if let requester { NSApp.yieldActivation(toApplicationWithBundleIdentifier: requester) }
        post(.unhandled, request: requestID)
        quitIfIdle()
    }

    private func post(_ kind: PluginEvent.Kind, request: String? = nil, time: Double? = nil) {
        DistributedNotificationCenter.default().postNotificationName(
            PluginProtocol.eventName,
            object: PluginEvent(kind: kind, plugin: id, request: request, time: time).json,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    // MARK: - Settings

    private func showSettings() {
        quitting?.cancel()
        if settings == nil {
            let window = SettingsWindow.make(updater: updates.updater)
            window.delegate = self
            settings = window
        }
        settings?.center()
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Quitting

    /// Gone once nothing's playing, saving or open — after a moment, so a
    /// video clicked again soon after doesn't start it over.
    private func quitIfIdle() {
        quitting?.cancel()
        quitting = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled,
                  !MediaViewer.isShowing, !ImageViewer.isShowing, !Downloads.shared.isBusy, self.settings?.isVisible != true
            else { return }
            NSApp.terminate(nil)
        }
    }

    /// No menu bar shows, but its keys still work while a player's in front.
    private static func menu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: String(localized: "Settings\u{2026}"), action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Quit Media Plugin"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = app
        let window = NSMenu(title: String(localized: "Window"))
        window.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: String(localized: "Toggle Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.control, .command]
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = window
        return main
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }
}

extension MediaPluginApp: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settings else { return }
        quitIfIdle()
    }
}
