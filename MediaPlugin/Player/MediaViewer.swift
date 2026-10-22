import AppKit
import AVKit

/// A window playing a page's video natively, from the stream `VideoPlugins`
/// found for it — apart from the page, which carries on as it was. A video
/// with nothing to play is handed back: its window goes, and Voyager lets
/// the page play it as it would have.
///
/// The window is Maipo's media browser (`MPOMediaBrowserController` and
/// `MPOMediaBrowserWindow`), with its sizing and look taken from Maipo's
/// binary: dark, with a see-through title bar — the system's, buttons and
/// all — grown out of the video's place in the panel to a
/// size that fits the video inside the screen's safe area, centred. An
/// ordinary window, never floating: Maipo puts its viewer at the source
/// window's level, but over a floating panel that leaves players stuck on
/// top of everything. The video
/// plays with sound, with the standard controls, from where the panel's
/// player was. A video already open in a window comes forward rather than
/// opening twice.
///
/// Closing is Maipo's too: Esc — its "exit gesture" — shrinks the window to
/// 80% about its centre as it fades, over 0.15 s, then closes it; the close
/// button and ⌘W close it at once. A double-click on the video goes full
/// screen and back, as in QuickTime Player.
@MainActor
final class MediaViewer: NSWindowController, NSWindowDelegate {
    struct Request {
        var video: MediaSites.Video
        /// The video's size as the panel knew it; zero when it didn't.
        var size: CGSize
        var startTime: Double
        /// Where it sits in the panel's viewport, in CSS pixels.
        var rect: CGRect
    }

    /// Open viewers, kept alive until closed.
    private static var open: [MediaViewer] = []

    /// The video this window plays, to bring it forward when it's asked for
    /// again.
    private var key = ""

    static let minSize = CGSize(width: 275, height: 250)
    /// The size assumed for a video until its own is known.
    private static let defaultSize = CGSize(width: 1280, height: 720)

    private let playerView = AVPlayerView()
    private let spinner = NSProgressIndicator()
    private var video: PlayableVideo?
    private var player: AVPlayer?
    private var loadTask: Task<Void, Never>?
    private var status: NSKeyValueObservation?
    /// Told where playback stopped, as the window closes — each click that
    /// asked for this video, the first and any after it.
    private var onClose: [(Double?) -> Void] = []
    /// Told there was nothing to play, as the window goes.
    private var onUnhandled: [() -> Void] = []

    /// Whether any player is open, so the plugin stays while one is.
    static var isShowing: Bool { !open.isEmpty }

    /// Plays `request` in a new window, growing out of `sourceFrame` (in
    /// screen coordinates). `cookies` are the page's site's, should the
    /// video still need looking up. `onClose` is told where playback
    /// stopped, so the page's copy can carry on there; `onUnhandled`, that
    /// there was nothing to play.
    static func show(
        _ request: Request,
        cookies: [HTTPCookie],
        sourceFrame: CGRect,
        onUnhandled: @escaping () -> Void,
        onClose: @escaping (Double?) -> Void
    ) {
        // Already open: it comes forward, and this click is answered with
        // the first's.
        if let viewer = open.first(where: { $0.key == request.video.key }) {
            viewer.onClose.append(onClose)
            viewer.onUnhandled.append(onUnhandled)
            viewer.bringToFront()
            return
        }
        let viewer = MediaViewer()
        viewer.key = request.video.key
        viewer.cookies = cookies
        if open.contains(where: { $0.window?.styleMask.contains(.fullScreen) == true }) {
            viewer.window?.collectionBehavior = [.fullScreenNone]
        }
        viewer.onClose = [onClose]
        viewer.onUnhandled = [onUnhandled]
        open.append(viewer)
        viewer.present(size: request.size, from: sourceFrame)
        viewer.loadTask = Task { [weak viewer] in
            let video = await VideoPlugins.shared.playable(request.video, cookies: cookies)
            guard let viewer, !Task.isCancelled else { return }
            if let video {
                viewer.play(video, from: request.startTime)
            } else {
                viewer.handBack()
            }
        }
    }

    private init() {
        let window = ViewerWindow(
            contentRect: CGRect(origin: .zero, size: Self.minSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.minSize = Self.minSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]

        playerView.controlsStyle = .floating
        // The player's own full screen moves the video to a window of its
        // own and leaves this one behind, empty, floating over it. The
        // window's full screen (green button, ⌃⌘F) takes the video with it.
        playerView.showsFullScreenToggleButton = false
        playerView.allowsPictureInPicturePlayback = true
        spinner.style = .spinning
        spinner.controlSize = .large
        spinner.translatesAutoresizingMaskIntoConstraints = false
        playerView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
        ])
        spinner.startAnimation(nil)
        // The player sits in a plain view filling the window, so what's laid
        // over it (the saving pie) is placed from the window's own edges —
        // the player keeps clear of the title bar.
        let container = NSView()
        playerView.translatesAutoresizingMaskIntoConstraints = true
        playerView.autoresizingMask = [.width, .height]
        container.addSubview(playerView)
        window.contentView = container
        playerView.frame = container.bounds
        super.init(window: window)
        window.delegate = self
        addSavingBadge()
        addInfoPanel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Playing

    private func play(_ video: PlayableVideo, from time: Double) {
        self.video = video
        let player = AVPlayer(playerItem: AVPlayerItem(asset: video.asset))
        self.player = player
        // The spinner stays until the stream is actually playing, and comes
        // back while it stops to buffer.
        status = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.showLoading(waiting) }
            }
        }
        playerView.player = player
        if let size = video.size { reshape(to: size) }
        Task { [weak self] in
            self?.audioTracks = try? await video.asset.loadMediaSelectionGroup(for: .audible)
        }
        // To the page's exact spot before it plays, so it doesn't show the
        // start first.
        guard time > 0 else { return player.play() }
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async { player.play() }
        }
    }

    private func showLoading(_ loading: Bool) {
        spinner.isHidden = !loading
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    /// Nothing to play: the window goes, and Voyager is told, so the page
    /// plays the video as it would have.
    private func handBack() {
        onClose = []
        let unhandled = onUnhandled
        onUnhandled = []
        if window?.isVisible == true { fadeOutThenClose() } else { window?.close() }
        unhandled.forEach { $0() }
    }

    /// The video's own shape, about the window's centre, when the panel
    /// didn't know it.
    private func reshape(to videoSize: CGSize) {
        guard let window, let screen = window.screen, videoSize.width > 0, videoSize.height > 0 else { return }
        let current = window.frame
        guard abs(videoSize.width / videoSize.height - current.width / current.height) > 0.02 else { return }
        var frame = Self.frame(for: videoSize, on: screen)
        frame.origin = CGPoint(x: current.midX - frame.width / 2, y: current.midY - frame.height / 2)
        window.setFrame(window.constrainFrameRect(frame, to: screen), display: true, animate: true)
    }

    // MARK: - Presenting

    private func present(size: CGSize, from sourceFrame: CGRect) {
        guard let window else { return }
        // The screen the video was on: the page's window is Voyager's,
        // another app's.
        let screen = NSScreen.screens.first { $0.frame.intersects(sourceFrame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let target = Self.frame(for: size.width > 0 && size.height > 0 ? size : Self.defaultSize, on: screen)
        if sourceFrame.isEmpty {
            window.setFrame(target, display: false)
            window.animationBehavior = .alertPanel
            bringToFront()
            window.animationBehavior = .default
        } else {
            // Maipo springs the frame out of the thumbnail
            // (POP, speed 36, no bounce): critically damped, so it rushes
            // out and settles without overshooting. A window's frame takes
            // only a curve, so it's this one, shaped like that spring.
            // Not run at all while the plugin isn't the active app — when
            // focus didn't come with the click — so the window is put at
            // its size once the animation would have ended, either way.
            window.setFrame(sourceFrame, display: false)
            // Where it really started: no smaller than its minimum size.
            let start = window.frame
            bringToFront()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 1, 0.3, 1)
                window.animator().setFrame(target, display: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                // Still where it started: the animation didn't run. Moved
                // since — grown, reshaped to the video, or by the user — it
                // stays as it is.
                if window.frame == start { window.setFrame(target, display: true) }
            }
        }
    }

    /// In front of every other player window. When Voyager isn't the active
    /// app, its becoming active a moment later brings back the window that
    /// was last key — an older player, over this one — so it's put in front
    /// again once that's happened.
    private func bringToFront() {
        orderInFront()
        guard !NSApp.isActive else { return }
        let observer = ObserverBox()
        observer.token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.orderInFront()
                if let token = observer.token { NotificationCenter.default.removeObserver(token) }
                observer.token = nil
            }
        }
        NSApp.activate()
    }

    private func orderInFront() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        for other in Self.open where other !== self {
            guard let behind = other.window, behind.isVisible else { continue }
            behind.order(.below, relativeTo: window.windowNumber)
        }
    }

    /// Maipo's window size for media of `size`: fit inside the screen's safe
    /// area — the visible frame less up to 15% (at most 200 points) at each
    /// side and 12% (at most 100) at top and bottom. Wider than the area's
    /// shape, it fits the width; otherwise the height — except media taller
    /// than three times its width, which keeps its width and gets a window
    /// three times as tall. Never under 275 × 250, centred in the visible
    /// frame.
    static func frame(for size: CGSize, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let safe = visible.insetBy(
            dx: min(visible.width * 0.15, 200),
            dy: min(visible.height * 0.12, 100)
        ).size
        var fitted = CGSize(width: min(safe.width, safe.height) / 2, height: min(safe.width, safe.height) / 2)
        if size.width > 0, size.height > 0 {
            let aspect = size.width / size.height
            if aspect > safe.width / safe.height {
                let width = min(safe.width, size.width)
                fitted = CGSize(width: width, height: width / aspect)
            } else {
                let height = min(safe.height, size.height)
                fitted = aspect >= 1.0 / 3
                    ? CGSize(width: aspect * height, height: height)
                    : CGSize(width: size.width, height: size.width * 3)
            }
        }
        let width = max(min(fitted.width, safe.width), minSize.width)
        let height = max(min(fitted.height, safe.height), minSize.height)
        return CGRect(
            x: (visible.minX + (visible.width - width) / 2).rounded(),
            y: (visible.minY + (visible.height - height) / 2).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    // MARK: - Saving

    private var cookies: [HTTPCookie] = []
    /// How far a save has got, from 0 to 1, while one is under way; the
    /// pie on the video shows it.
    private var saving: Double? {
        didSet { showSaving() }
    }
    private let savingBadge = NSVisualEffectView()
    private static let badgeInset: CGFloat = 12
    private static let badgeSize: CGFloat = 22
    private let savingPie = PieView()
    private let savedMark = NSImageView()
    /// Where the video was saved, once it has been.
    private var savedFile: URL?

    /// The video's right-click menu: the video info, on or off; then
    /// Download Video, "Downloading… 42%" while it does, then Show in Finder.
    fileprivate func contextMenu() -> NSMenu? {
        guard let video else { return nil }
        let menu = NSMenu()
        let showing = infoUpdates != nil
        menu.addItem(withTitle: showing ? String(localized: "Hide Video Info") : String(localized: "Show Video Info"),
                     action: #selector(toggleInfo), keyEquivalent: "")
        let choices = [resolutionMenu(for: video), audioMenu()].compactMap { $0 }
        if !choices.isEmpty {
            menu.addItem(.separator())
            choices.forEach(menu.addItem)
        }
        if video.saving != nil {
            menu.addItem(.separator())
            if let savedFile {
                menu.addItem(withTitle: String(localized: "Show in Finder"), action: #selector(showSaved), keyEquivalent: "")
            } else if let saving {
                let item = menu.addItem(withTitle: String(localized: "Downloading\u{2026} \(Int(saving * 100))%"), action: nil, keyEquivalent: "")
                item.isEnabled = false
            } else if let choices = video.saving?.choices, choices.count > 1 {
                // Each size and codec it comes in.
                let download = menu.addItem(withTitle: String(localized: "Download Video"), action: nil, keyEquivalent: "")
                let sizes = NSMenu()
                for (index, choice) in choices.enumerated() {
                    let item = sizes.addItem(withTitle: choice.title, action: #selector(saveChoice), keyEquivalent: "")
                    item.tag = index
                    item.target = self
                }
                download.submenu = sizes
            } else {
                menu.addItem(withTitle: String(localized: "Download Video"), action: #selector(saveVideo), keyEquivalent: "")
            }
        }
        menu.items.forEach { $0.target = self }
        menu.autoenablesItems = false
        return menu
    }

    /// While saving, a pie filling up on the video's top-right corner, in
    /// the player's controls' style; saved, the full pie with a checkmark on
    /// it, for a moment.
    private func addSavingBadge() {
        savedMark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Saved")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
        savedMark.contentTintColor = .white
        savedMark.isHidden = true
        savingBadge.material = .hudWindow
        savingBadge.blendingMode = .withinWindow
        savingBadge.state = .active
        savingBadge.wantsLayer = true
        savingBadge.layer?.cornerRadius = Self.badgeSize / 2
        savingBadge.alphaValue = 0
        for view in [savingBadge, savingPie, savedMark] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
        savingBadge.addSubview(savingPie)
        savingBadge.addSubview(savedMark)
        window?.contentView?.addSubview(savingBadge, positioned: .above, relativeTo: playerView)
        guard let container = window?.contentView else { return }
        NSLayoutConstraint.activate([
            savingBadge.widthAnchor.constraint(equalToConstant: Self.badgeSize),
            savingBadge.heightAnchor.constraint(equalToConstant: Self.badgeSize),
            // The same gap from the top as from the side: the title bar's
            // buttons are on the other side.
            savingBadge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.badgeInset),
            savingBadge.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.badgeInset),
            // The whole badge is the pie.
            savingPie.centerXAnchor.constraint(equalTo: savingBadge.centerXAnchor),
            savingPie.centerYAnchor.constraint(equalTo: savingBadge.centerYAnchor),
            savingPie.widthAnchor.constraint(equalTo: savingBadge.widthAnchor),
            savingPie.heightAnchor.constraint(equalTo: savingBadge.heightAnchor),
            savedMark.centerXAnchor.constraint(equalTo: savingBadge.centerXAnchor),
            savedMark.centerYAnchor.constraint(equalTo: savingBadge.centerYAnchor),
        ])
    }

    private func showSaving() {
        if let saving {
            savingPie.progress = saving
            savingPie.isHidden = false
            savedMark.isHidden = true
            fadeBadge(to: 1)
        } else if savedFile != nil {
            // The pie, full, with a checkmark on it: the same circle.
            savingPie.progress = 1
            savingPie.isHidden = false
            savedMark.isHidden = false
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.fadeBadge(to: 0)
            }
        } else {
            fadeBadge(to: 0)
        }
    }

    private func fadeBadge(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            savingBadge.animator().alphaValue = alpha
        }
    }

    @objc private func showSaved() {
        guard let savedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedFile])
    }

    @objc private func saveVideo() {
        save(as: nil)
    }

    @objc private func saveChoice(_ sender: NSMenuItem) {
        guard let choices = video?.saving?.choices, choices.indices.contains(sender.tag) else { return }
        save(as: choices[sender.tag])
    }

    /// Saves the video as `choice`, with the sound track that's playing.
    private func save(as choice: PlayableVideo.SaveChoice?) {
        guard saving == nil, let video, let saving = video.saving else { return }
        let downloads = Downloads.shared
        let destination = downloads.destination(for: saving.filename)
        let language = audioTracks
            .flatMap { player?.currentItem?.currentMediaSelection.selectedMediaOption(in: $0) }?
            .extendedLanguageTag
        let cookies = cookies
        self.saving = 0
        // Carries on if the window closes; the file still lands in Downloads.
        Task { [weak self] in
            do {
                try await VideoPlugins.shared.save(video, as: choice, language: language, cookies: cookies, to: destination) { done in
                    // Word of progress can land late, after the save is
                    // over, or out of order: only forward, and only while
                    // saving.
                    guard let self, let saving = self.saving else { return }
                    self.saving = max(saving, done)
                }
                downloads.saved(destination)
                self?.savedFile = destination
            } catch {
                downloads.failed(destination, reason: error.localizedDescription)
            }
            self?.saving = nil
        }
    }

    // MARK: - Resolution and Audio

    /// The tallest picture AVPlayer may pick, or nil to leave it to the
    /// line and the window.
    private var maxSize: CGSize?
    /// The video's sound tracks, when it has a choice of them.
    private var audioTracks: AVMediaSelectionGroup?

    /// Resolution ▸ Auto, then each size the video comes in, tallest first.
    /// A ceiling rather than a lock: AVPlayer still goes lower on a slow
    /// line, and switches without starting over.
    private func resolutionMenu(for video: PlayableVideo) -> NSMenuItem? {
        var sizes: [CGFloat: CGSize] = [:]
        for case let size? in video.streams.values.map(\.size) { sizes[size.height] = size }
        guard sizes.count > 1 else { return nil }
        let menu = NSMenu()
        let auto = menu.addItem(withTitle: String(localized: "Auto"), action: #selector(chooseResolution), keyEquivalent: "")
        auto.state = maxSize == nil ? .on : .off
        for size in sizes.values.sorted(by: { $0.height > $1.height }) {
            let height = PlayableVideo.quality(of: size)
            let title = PlayableVideo.qualityName(height)
            let item = menu.addItem(withTitle: title, action: #selector(chooseResolution), keyEquivalent: "")
            item.representedObject = NSValue(size: size)
            item.state = maxSize == size ? .on : .off
        }
        menu.items.forEach { $0.target = self }
        let item = NSMenuItem(title: String(localized: "Resolution"), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func chooseResolution(_ sender: NSMenuItem) {
        maxSize = (sender.representedObject as? NSValue)?.sizeValue
        player?.currentItem?.preferredMaximumResolution = maxSize ?? .zero
    }

    /// Audio ▸ each sound track: the original, and the languages it's
    /// dubbed into.
    private func audioMenu() -> NSMenuItem? {
        guard let audioTracks, audioTracks.options.count > 1, let item = player?.currentItem else { return nil }
        let selected = item.currentMediaSelection.selectedMediaOption(in: audioTracks)
        let menu = NSMenu()
        for option in audioTracks.options {
            let name = option.extendedLanguageTag.flatMap { video?.sounds[$0]?.name } ?? option.displayName
            let entry = menu.addItem(withTitle: name, action: #selector(chooseAudio), keyEquivalent: "")
            entry.representedObject = option
            entry.state = option == selected ? .on : .off
            entry.target = self
        }
        let audio = NSMenuItem(title: String(localized: "Audio"), action: nil, keyEquivalent: "")
        audio.submenu = menu
        return audio
    }

    @objc private func chooseAudio(_ sender: NSMenuItem) {
        guard let audioTracks, let option = sender.representedObject as? AVMediaSelectionOption else { return }
        player?.currentItem?.select(option, in: audioTracks)
    }

    // MARK: - Video Info

    /// What's playing — the codec, the size it's decoded at, the bitrate —
    /// in the top-left corner, updated each second, while it's on.
    private let infoPanel = NSVisualEffectView()
    private let infoText = NSTextField(labelWithString: "")
    private var infoUpdates: Task<Void, Never>?
    /// The decoded pictures, for their real size: an HLS item's
    /// `presentationSize` lags behind its switches.
    private var infoOutput: AVPlayerItemVideoOutput?
    private var decodedSize: CGSize?
    /// What a file's tracks say they are, read once. An HLS stream's
    /// tracks say nothing: its codec is yt-dlp's, by the stream playing.
    private var codecs: [AVMediaType: String]?
    private var codecReads = 0

    private func addInfoPanel() {
        infoPanel.material = .hudWindow
        infoPanel.blendingMode = .withinWindow
        infoPanel.state = .active
        infoPanel.wantsLayer = true
        infoPanel.layer?.cornerRadius = 8
        infoPanel.isHidden = true
        infoText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        infoText.textColor = .white
        infoText.maximumNumberOfLines = 0
        for view in [infoPanel, infoText] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
        infoPanel.addSubview(infoText)
        guard let container = window?.contentView else { return }
        container.addSubview(infoPanel, positioned: .above, relativeTo: playerView)
        NSLayoutConstraint.activate([
            infoPanel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.badgeInset),
            // Below the title bar's buttons.
            infoPanel.topAnchor.constraint(equalTo: container.topAnchor, constant: 36),
            infoText.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor, constant: 8),
            infoText.trailingAnchor.constraint(equalTo: infoPanel.trailingAnchor, constant: -8),
            infoText.topAnchor.constraint(equalTo: infoPanel.topAnchor, constant: 6),
            infoText.bottomAnchor.constraint(equalTo: infoPanel.bottomAnchor, constant: -6),
        ])
    }

    @objc private func toggleInfo() {
        if let infoUpdates {
            infoUpdates.cancel()
            self.infoUpdates = nil
            if let infoOutput { player?.currentItem?.remove(infoOutput) }
            infoOutput = nil
            infoPanel.isHidden = true
            return
        }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        player?.currentItem?.add(output)
        infoOutput = output
        decodedSize = nil
        infoPanel.isHidden = false
        infoUpdates = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateInfo()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func updateInfo() async {
        guard let video, let item = player?.currentItem else { return }
        let now = item.currentTime()
        if let infoOutput, infoOutput.hasNewPixelBuffer(forItemTime: now),
           let picture = infoOutput.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: nil) {
            decodedSize = CGSize(width: CVPixelBufferGetWidth(picture), height: CVPixelBufferGetHeight(picture))
        }
        let log = item.accessLog()?.events ?? []
        // The picture's own entry: the log also has the sound's.
        let event = log.last { $0.uri.flatMap { video.streams[$0] } != nil } ?? log.last
        let stream = event?.uri.flatMap { video.streams[$0] }
        if codecs == nil, !item.tracks.isEmpty {
            codecReads += 1
            var found: [AVMediaType: String] = [:]
            for track in item.tracks {
                guard let asset = track.assetTrack,
                      let description = try? await asset.load(.formatDescriptions).first else { continue }
                found[asset.mediaType] = Self.fourCC(CMFormatDescriptionGetMediaSubType(description))
            }
            // Kept once every track has said — or for HLS, whose tracks
            // never do — or after a few tries, with what has.
            if found.count == item.tracks.count || video.streams.values.contains(where: \.isHLS) || codecReads >= 3 {
                codecs = found
            }
        }
        let codecs = codecs ?? [:]
        let size = decodedSize ?? (item.presentationSize == .zero ? nil : item.presentationSize)
        let fps = stream?.fps ?? item.tracks.lazy.map(\.currentVideoFrameRate).first { $0 > 0 }.map(Double.init)
        let track = audioTracks.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) }
        let sound = track?.extendedLanguageTag.flatMap { video.sounds[$0] } ?? video.firstSound

        var lines: [String] = []
        lines.append("Stream   " + (video.isJoined ? "HLS, \(video.streams.count) sizes" : video.streams.values.first?.isHLS == true ? "HLS" : "File"))
        lines.append("Video    " + [
            Self.codecName(stream?.codec ?? codecs[.video]),
            size.map { "\(Int($0.width))\u{00D7}\(Int($0.height))" },
            fps.map { String(format: "%g fps", ($0 * 100).rounded() / 100) },
        ].compactMap { $0 }.joined(separator: " \u{00B7} "))
        lines.append("Audio    " + [
            Self.codecName(sound?.codec ?? codecs[.audio]),
            sound?.bitrate.map { "\(Int($0)) kbps" },
            sound?.name ?? track?.displayName,
        ].compactMap { $0 }.joined(separator: " \u{00B7} "))
        if let event {
            lines.append("Bitrate  " + Self.rate(event.indicatedBitrate) + " stream \u{00B7} " + Self.rate(event.observedBitrate) + " network")
        }
        if let range = item.loadedTimeRanges.map(\.timeRangeValue).first(where: { $0.containsTime(now) }) {
            lines.append(String(format: "Buffer   %.1f s ahead", range.end.seconds - now.seconds))
        }
        let dropped = log.reduce(0) { $0 + max($1.numberOfDroppedVideoFrames, 0) }
        lines.append("Dropped  \(dropped) frames")
        let view = playerView.convertToBacking(playerView.bounds).size
        lines.append("View     \(Int(view.width))\u{00D7}\(Int(view.height)) px")
        infoText.stringValue = lines.joined(separator: "\n")
    }

    private static func codecName(_ codec: String?) -> String? {
        guard let codec else { return nil }
        let names = ["avc1": "H.264", "h264": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "vp09": "VP9", "vp9": "VP9",
                     "av01": "AV1", "mp4a": "AAC", "aac ": "AAC", "opus": "Opus", "Opus": "Opus", "ec-3": "E-AC-3", "ac-3": "AC-3"]
        let name = names.first { codec.hasPrefix($0.key) }?.value
        let code = codec.trimmingCharacters(in: .whitespaces)
        guard let name, name.caseInsensitiveCompare(code) != .orderedSame else { return name ?? code }
        return "\(name) (\(code))"
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }, as: UTF8.self)
    }

    private static func rate(_ bitsPerSecond: Double) -> String {
        guard bitsPerSecond > 0 else { return "\u{2013}" }
        return bitsPerSecond >= 1_000_000 ? String(format: "%.1f Mbps", bitsPerSecond / 1_000_000) : "\(Int(bitsPerSecond / 1000)) kbps"
    }

    // MARK: - Closing

    /// Maipo's `fadeOutThenClose`: to 80% about the centre, and transparent,
    /// over 0.15 s, eased in and out; then closed.
    fileprivate func fadeOutThenClose() {
        guard let window, window.isVisible else { return }
        // Silent at once, whatever becomes of the animation.
        player?.pause()
        let frame = window.frame
        let small = frame.insetBy(dx: frame.width * 0.1, dy: frame.height * 0.1)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(small, display: true)
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { window.close() }
        }
    }

    // MARK: - NSWindowDelegate

    /// One player full screen at a time: while this one is, the others
    /// can't be — their green button zooms instead.
    func windowWillEnterFullScreen(_ notification: Notification) {
        for other in Self.open where other !== self {
            other.window?.collectionBehavior = [.fullScreenNone]
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        for other in Self.open where other !== self {
            other.window?.collectionBehavior = [.fullScreenPrimary]
        }
    }

    func windowWillClose(_ notification: Notification) {
        loadTask?.cancel()
        infoUpdates?.cancel()
        infoUpdates = nil
        let time = player?.currentTime().seconds
        let closes = onClose
        onClose = []
        onUnhandled = []
        closes.forEach { $0(time.flatMap { $0.isFinite ? $0 : nil }) }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        status = nil
        playerView.player = nil
        player = nil
        video = nil
        Self.open.removeAll { $0 === self }
        // Closed while full screen: the others may go full screen again.
        if window?.styleMask.contains(.fullScreen) == true {
            for other in Self.open { other.window?.collectionBehavior = [.fullScreenPrimary] }
        }
    }
}

// MARK: - Window

/// Esc closes it; its title bar is the system's, as it is.
private final class ViewerWindow: NSWindow {
    /// Esc: Maipo's exit gesture. In full screen, the system's own handling.
    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) {
            super.cancelOperation(sender)
        } else {
            (windowController as? MediaViewer)?.fadeOutThenClose()
        }
    }

    /// A right-click (or ⌃-click) on the video opens its menu — video info,
    /// resolution, audio, Download Video — rather than the player's.
    private func showsContextMenu(_ event: NSEvent) -> Bool {
        let rightClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard rightClick, let contentView, contentLayoutRect.contains(event.locationInWindow),
              let menu = (windowController as? MediaViewer)?.contextMenu()
        else { return false }
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        return true
    }

    /// A double-click on the video goes full screen, or back — not on the
    /// player's controls along the bottom, where it's theirs.
    override func sendEvent(_ event: NSEvent) {
        if showsContextMenu(event) { return }
        // Not while another player is full screen: this one can't be.
        if event.type == .leftMouseDown, event.clickCount == 2, onVideo(event.locationInWindow),
           !collectionBehavior.contains(.fullScreenNone) {
            toggleFullScreen(nil)
            return
        }
        super.sendEvent(event)
    }

    /// How far up from the bottom the player's floating controls reach.
    private static let controlsHeight: CGFloat = 80

    /// On the video itself: under the title bar — its buttons and the save
    /// button — above the player's controls, and in from the edges, where
    /// a double-click resizes.
    private func onVideo(_ point: NSPoint) -> Bool {
        let area = contentLayoutRect.insetBy(dx: 8, dy: 0)
        return area.contains(point) && point.y > Self.controlsHeight
    }
}

/// A notification observer's token, for the observer to remove itself.
final class ObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?
}

/// A pie filling clockwise from twelve o'clock across the whole badge, in
/// translucent white over its dark circle — never solid, so the badge
/// still reads as one.
private final class PieView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let fraction = min(max(progress, 0), 1)
        guard fraction > 0 else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2
        let wedge = NSBezierPath()
        wedge.move(to: center)
        // Non-flipped: 90° is twelve o'clock, and clockwise runs downward.
        wedge.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        wedge.close()
        NSColor.white.withAlphaComponent(0.3).setFill()
        wedge.fill()
    }
}
