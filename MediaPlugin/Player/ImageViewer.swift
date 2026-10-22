import AppKit
import UniformTypeIdentifiers

/// A window showing a page's photos — the one clicked, with the others
/// posted with it — in full, one at a time.
///
/// Maipo's media browser again (`MPOMediaBrowserView`,
/// `MPOMediaBrowserItemView`), as `MediaViewer` is for a video: the same
/// dark window, grown out of the photo's place in the panel, closed the same
/// ways. The photos sit side by side, 30 points apart, and slide by — with
/// ← and →, a swipe, or the arrow that shows at the side the pointer is
/// near, 66 points in. Each is fitted to the window, never enlarged past its
/// own size, and zooms up to three times — a pinch, or = and −, by 1.3 —
/// and pans by dragging. Maipo's toolbar has ‹ ›, the photo's place among
/// them, "2 / 4", and zoom. Space and a double-click close it,
/// as Esc does. The page's copy shows until the full photo is in.
@MainActor
final class ImageViewer: NSWindowController, NSWindowDelegate {
    struct Request {
        var images: [PluginRequest.Image]
        /// The one clicked.
        var index: Int
        /// The page they're on, sent with each photo's request as the page
        /// would.
        var referrer: URL?
    }

    /// Open viewers, kept alive until closed.
    private static var open: [ImageViewer] = []

    /// Whether any is open, so the plugin stays while one is.
    static var isShowing: Bool { !open.isEmpty }

    /// The photos this window shows, to bring it forward when they're asked
    /// for again.
    private var key = ""
    private var referrer: URL?
    private var photos: [Photo] = []
    private var index = 0
    private let pager = PagerView()
    private let previous = NavigationButton(symbol: "chevron.left")
    private let next = NavigationButton(symbol: "chevron.right")
    private let place = NSTextField(labelWithString: "")
    private let paging = NSSegmentedControl()
    private let zooming = NSSegmentedControl()
    private var loads: [Task<Void, Never>] = []
    /// Whether the window has taken the shape of the photo clicked yet.
    private var shaped = false
    /// Told as the window closes — each click that asked for these photos.
    private var onClose: [() -> Void] = []

    /// Maipo's: arrows 66 points in from the sides, shown with the pointer
    /// within 50 of one.
    private static let arrowInset: CGFloat = 66
    private static let arrowReach: CGFloat = 50
    static let zoomStep: CGFloat = 1.3
    static let maxZoom: CGFloat = 3

    /// One photo: where it's fetched from, what's shown of it so far, and
    /// its file, once in, for saving and copying.
    fileprivate struct Photo {
        var url: URL
        var preview: URL?
        var page: PhotoPage
        var data: Data?
        var started = false
    }

    /// Shows `request` in a new window, growing out of `sourceFrame` (in
    /// screen coordinates). `onClose` is told as it closes.
    static func show(_ request: Request, sourceFrame: CGRect, onClose: @escaping () -> Void) {
        let urls = request.images.compactMap { URL(string: $0.url) }
        guard !urls.isEmpty else { return onClose() }
        let index = min(max(request.index, 0), urls.count - 1)
        let key = urls.map(\.absoluteString).joined(separator: "\n")
        // Already open: it comes forward at the photo clicked.
        if let viewer = open.first(where: { $0.key == key }) {
            viewer.onClose.append(onClose)
            viewer.go(to: index, animated: false)
            viewer.bringToFront()
            return
        }
        let viewer = ImageViewer()
        viewer.key = key
        viewer.referrer = request.referrer
        viewer.onClose = [onClose]
        viewer.photos = request.images.compactMap { image in
            URL(string: image.url).map { Photo(url: $0, preview: image.preview.flatMap(URL.init(string:)), page: PhotoPage()) }
        }
        viewer.pager.pages = viewer.photos.map(\.page)
        open.append(viewer)
        viewer.go(to: index, animated: false)
        // Until the photo's own size is in, the shape of its place in the
        // panel — X crops a few photos to a grid, but one is shown whole.
        let shape = sourceFrame.isEmpty ? CGSize(width: 4, height: 3) : sourceFrame.size
        viewer.present(size: CGSize(width: shape.width * 100, height: shape.height * 100), from: sourceFrame)
        viewer.updateArrows(at: nil)
    }

    private init() {
        let window = ImageWindow(
            contentRect: CGRect(origin: .zero, size: MediaViewer.minSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.minSize = MediaViewer.minSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.acceptsMouseMovedEvents = true

        let container = TrackingView()
        pager.translatesAutoresizingMaskIntoConstraints = true
        pager.autoresizingMask = [.width, .height]
        container.addSubview(pager)
        window.contentView = container
        pager.frame = container.bounds
        super.init(window: window)
        window.delegate = self
        container.onMove = { [weak self] point in self?.pointerMoved(to: point) }
        pager.onPage = { [weak self] index in self?.go(to: index, animated: true) }
        addArrows(to: container)
        addToolbar(to: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Paging

    /// To the photo at `index`, sliding there; it and its neighbours load.
    private func go(to index: Int, animated: Bool) {
        guard photos.indices.contains(index) else { return pager.settle(animated: true) }
        if index != self.index { photos[self.index].page.resetZoom() }
        self.index = index
        pager.show(index, animated: animated)
        for i in [index, index + 1, index - 1] where photos.indices.contains(i) { load(i) }
        place.stringValue = photos.count > 1 ? "\(index + 1) / \(photos.count)" : ""
        paging.setEnabled(index > 0, forSegment: 0)
        paging.setEnabled(index < photos.count - 1, forSegment: 1)
        updateArrows(at: pointer)
    }

    /// Where the pointer is over the window's content.
    private var pointer: NSPoint? {
        guard let window, let view = window.contentView else { return nil }
        return view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }

    fileprivate func step(_ delta: Int) {
        go(to: index + delta, animated: true)
    }

    fileprivate func zoom(by factor: CGFloat) {
        photos[index].page.zoom(by: factor)
    }

    fileprivate var isZoomed: Bool { photos[index].page.isZoomed }

    // MARK: - Loading

    /// The page's copy and the full photo, fetched side by side as the page
    /// would fetch them: the page's copy shows unless the full photo beat
    /// it in. Neither in, the page says so.
    private func load(_ i: Int) {
        guard !photos[i].started else { return }
        photos[i].started = true
        let photo = photos[i]
        let referrer = referrer
        if let preview = photo.preview {
            loads.append(Task { [weak self] in
                guard let data = await Self.fetch(preview, referrer: referrer), let image = NSImage(data: data),
                      !Task.isCancelled, let self, self.photos[i].data == nil
                else { return }
                self.display(image, at: i, full: false)
            })
        }
        loads.append(Task { [weak self] in
            let data = await Self.fetch(photo.url, referrer: referrer)
            guard !Task.isCancelled, let self else { return }
            guard let data, let image = NSImage(data: data) else {
                // The page's copy, should it come after, does instead.
                if !photo.page.hasImage { photo.page.showFailed() }
                return
            }
            self.photos[i].data = data
            self.display(image, at: i, full: true)
        })
    }

    /// The window takes the clicked photo's size once it's in, as Maipo's
    /// does — its shape from the page's copy till then.
    private func display(_ image: NSImage, at i: Int, full: Bool) {
        photos[i].page.image = image
        guard i == index, !shaped else { return }
        let size = image.pixelSize
        if full {
            shaped = true
            reshape(to: size)
        } else {
            reshape(to: CGSize(width: size.width * 100, height: size.height * 100))
        }
    }

    private static func fetch(_ url: URL, referrer: URL?) async -> Data? {
        var request = URLRequest(url: url)
        if let referrer { request.setValue(referrer.absoluteString, forHTTPHeaderField: "Referer") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400
        else { return nil }
        return data
    }

    // MARK: - Presenting

    /// The photo's own shape, about the window's centre.
    private func reshape(to size: CGSize) {
        guard let window, let screen = window.screen ?? NSScreen.main, size.width > 0, size.height > 0,
              !window.styleMask.contains(.fullScreen)
        else { return }
        let current = window.frame
        var frame = MediaViewer.frame(for: size, on: screen)
        guard abs(frame.width - current.width) > 2 || abs(frame.height - current.height) > 2 else { return }
        frame.origin = CGPoint(x: current.midX - frame.width / 2, y: current.midY - frame.height / 2)
        window.setFrame(window.constrainFrameRect(frame, to: screen), display: true, animate: true)
    }

    /// As `MediaViewer` presents a video: sprung out of the photo's place,
    /// or popped up like an alert with none.
    private func present(size: CGSize, from sourceFrame: CGRect) {
        guard let window else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(sourceFrame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let target = MediaViewer.frame(for: size, on: screen)
        if sourceFrame.isEmpty {
            window.setFrame(target, display: false)
            window.animationBehavior = .alertPanel
            bringToFront()
            window.animationBehavior = .default
            return
        }
        window.setFrame(sourceFrame, display: false)
        let start = window.frame
        bringToFront()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 1, 0.3, 1)
            window.animator().setFrame(target, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if window.frame == start { window.setFrame(target, display: true) }
        }
    }

    /// In front, and — when the plugin isn't active yet — again once it is,
    /// over whichever window that brings back.
    private func bringToFront() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        guard !NSApp.isActive else { return }
        let observer = ObserverBox()
        observer.token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window?.makeKeyAndOrderFront(nil)
                if let token = observer.token { NotificationCenter.default.removeObserver(token) }
                observer.token = nil
            }
        }
        NSApp.activate()
    }

    // MARK: - Arrows and Place

    private func addArrows(to container: NSView) {
        for (button, action) in [(previous, #selector(showPrevious)), (next, #selector(showNext))] {
            button.button.target = self
            button.button.action = action
            button.alphaValue = 0
            button.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(button, positioned: .above, relativeTo: pager)
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            previous.centerXAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.arrowInset),
            next.centerXAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.arrowInset),
        ])
    }

    // MARK: - Toolbar

    private static let pagingItem = NSToolbarItem.Identifier("paging")
    private static let placeItem = NSToolbarItem.Identifier("place")
    private static let zoomItem = NSToolbarItem.Identifier("zoom")

    /// Maipo's toolbar, its controls large: ‹ › by the window's buttons, the
    /// photo's place, "2 / 4", in the middle, and zoom − + at the end.
    private func addToolbar(to window: NSWindow) {
        place.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        place.textColor = .white
        for (control, symbols, labels, action) in [
            (paging, ["chevron.left", "chevron.right"], [String(localized: "Previous"), String(localized: "Next")], #selector(pageFromToolbar(_:))),
            (zooming, ["minus.magnifyingglass", "plus.magnifyingglass"], [String(localized: "Zoom Out"), String(localized: "Zoom In")], #selector(zoomFromToolbar(_:))),
        ] {
            control.segmentCount = 2
            control.trackingMode = .momentary
            control.controlSize = .large
            control.target = self
            control.action = action
            for (segment, symbol) in symbols.enumerated() {
                control.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: labels[segment]), forSegment: segment)
                control.setToolTip(labels[segment], forSegment: segment)
                control.setWidth(36, forSegment: segment)
            }
        }
        let toolbar = NSToolbar(identifier: "ImageViewer")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.placeItem]
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    @objc private func pageFromToolbar(_ sender: NSSegmentedControl) {
        step(sender.selectedSegment == 0 ? -1 : 1)
    }

    @objc private func zoomFromToolbar(_ sender: NSSegmentedControl) {
        zoom(by: sender.selectedSegment == 0 ? 1 / Self.zoomStep : Self.zoomStep)
    }

    @objc private func showPrevious() { step(-1) }
    @objc private func showNext() { step(1) }

    private func pointerMoved(to point: NSPoint) {
        updateArrows(at: point)
    }

    /// Only the arrow the pointer is near, and only where there's a photo
    /// that way.
    private func updateArrows(at point: NSPoint?) {
        for (button, possible) in [(previous, index > 0), (next, index < photos.count - 1)] {
            let near = point.map { button.frame.insetBy(dx: -Self.arrowReach, dy: -Self.arrowReach).contains($0) } ?? false
            let alpha: CGFloat = possible && near ? 1 : 0
            button.button.isEnabled = possible
            guard button.alphaValue != alpha else { continue }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                button.animator().alphaValue = alpha
            }
        }
    }


    // MARK: - Menu and Saving

    fileprivate func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let loaded = photos[index].data != nil
        menu.addItem(withTitle: String(localized: "Copy Image"), action: loaded ? #selector(copyImage) : nil, keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: String(localized: "Copy Image Link"), action: #selector(copyAddress), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Save Image"), action: loaded ? #selector(saveImage) : nil, keyEquivalent: "")
            .target = self
        if photos.count > 1 {
            menu.addItem(withTitle: String(localized: "Save All \(photos.count) Images"), action: #selector(saveAll), keyEquivalent: "")
                .target = self
        }
        return menu
    }

    @objc private func saveImage() {
        guard let data = photos[index].data else { return }
        let url = photos[index].url
        Self.write(data, to: Downloads.shared.destination(for: Self.filename(for: url, data: data)))
    }

    /// Each photo, fetched first if it isn't in yet — its file spoken for
    /// before, so the plugin stays till it's in, with the window closed.
    @objc private func saveAll() {
        let referrer = referrer
        for photo in photos {
            let destination = Downloads.shared.destination(for: Self.filename(for: photo.url, data: photo.data))
            if let data = photo.data {
                Self.write(data, to: destination)
                continue
            }
            Task {
                guard let data = await Self.fetch(photo.url, referrer: referrer) else {
                    return Downloads.shared.failed(destination, reason: String(localized: "The image couldn't be downloaded."))
                }
                Self.write(data, to: destination)
            }
        }
    }

    @objc private func copyImage() {
        guard let data = photos[index].data, let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    @objc private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(photos[index].url.absoluteString, forType: .string)
    }

    /// A photo's name in the downloads folder, for its file — X names its
    /// by a `format` query, not an extension; the file's own type, when
    /// it's in, says best.
    private static func filename(for url: URL, data: Data?) -> String {
        let name = url.lastPathComponent.isEmpty ? "Image" : url.lastPathComponent
        guard (name as NSString).pathExtension.isEmpty else { return name }
        let format = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "format" }?.value
        let type = data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap(CGImageSourceGetType)
            .flatMap { UTType($0 as String)?.preferredFilenameExtension }
        return (type ?? format).map { "\(name).\($0)" } ?? name
    }

    /// Into its spot in the downloads folder, spoken for already.
    private static func write(_ data: Data, to destination: URL) {
        do {
            try data.write(to: destination)
            Downloads.shared.saved(destination)
        } catch {
            Downloads.shared.failed(destination, reason: error.localizedDescription)
        }
    }

    // MARK: - Closing

    /// Maipo's `fadeOutThenClose`, as for a video.
    fileprivate func fadeOutThenClose() {
        guard let window, window.isVisible else { return }
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

    func windowDidResize(_ notification: Notification) {
        pager.settle(animated: false)
    }

    func windowWillClose(_ notification: Notification) {
        loads.forEach { $0.cancel() }
        let closes = onClose
        onClose = []
        closes.forEach { $0() }
        Self.open.removeAll { $0 === self }
    }
}

extension ImageViewer: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.pagingItem, .flexibleSpace, Self.placeItem, .flexibleSpace, Self.zoomItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.pagingItem, Self.zoomItem, Self.placeItem:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = id == Self.pagingItem ? paging : id == Self.zoomItem ? zooming : place
            return item
        default:
            return nil
        }
    }
}

// MARK: - Window

/// Maipo's keys: ← and → page, = and − zoom, Esc and Space close — so does
/// a double-click on the photo. A right-click opens the photo's menu.
private final class ImageWindow: NSWindow {
    private var viewer: ImageViewer? { windowController as? ImageViewer }

    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) {
            super.cancelOperation(sender)
        } else {
            viewer?.fadeOutThenClose()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123: viewer?.step(-1)
        case 124: viewer?.step(1)
        case 24: viewer?.zoom(by: ImageViewer.zoomStep)
        case 27: viewer?.zoom(by: 1 / ImageViewer.zoomStep)
        case 49: viewer?.fadeOutThenClose()
        default: super.keyDown(with: event)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        let inside = contentLayoutRect.contains(event.locationInWindow)
        let rightClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        if rightClick, inside, let contentView, let menu = viewer?.contextMenu() {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
            return
        }
        let hit = contentView.flatMap { $0.hitTest($0.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow) }
        // Not while a zoomed photo's being dragged about.
        if event.type == .leftMouseDown, event.clickCount == 2, inside, !(hit is NSButton), viewer?.isZoomed != true {
            viewer?.fadeOutThenClose()
            return
        }
        super.sendEvent(event)
    }
}

/// The window's content, telling where the pointer goes over it.
private final class TrackingView: NSView {
    var onMove: ((NSPoint) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onMove?(NSPoint(x: -1000, y: -1000))
    }
}

/// An arrow at the side, over the photo: a white chevron on a glass
/// circle.
private final class NavigationButton: NSView {
    private static let diameter: CGFloat = 44
    let button: NSButton

    init(symbol: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let chevron = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        button = NSButton(image: chevron, target: nil, action: nil)
        button.isBordered = false
        button.contentTintColor = .white
        super.init(frame: .zero)
        let glass = Glass.around(button, cornerRadius: Self.diameter / 2)
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        widthAnchor.constraint(equalToConstant: Self.diameter).isActive = true
        heightAnchor.constraint(equalToConstant: Self.diameter).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The arrows over the photo sit on glass:
/// Liquid Glass where the system has it, a dark blur before.
@MainActor
private enum Glass {
    static func around(_ content: NSView, cornerRadius: CGFloat, padding: NSEdgeInsets = NSEdgeInsetsZero) -> NSView {
        // The content held in from the glass's edges by `padding`.
        let holder = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: padding.left),
            content.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -padding.right),
            content.topAnchor.constraint(equalTo: holder.topAnchor, constant: padding.top),
            content.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -padding.bottom),
        ])
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = holder
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        holder.frame = blur.bounds
        holder.autoresizingMask = [.width, .height]
        blur.addSubview(holder)
        return blur
    }
}

// MARK: - Pages

/// The photos side by side, 30 points apart, one filling the view at a time.
/// A sideways swipe drags them along; let go past a fifth of the way — or
/// with a flick — and the next one slides in.
private final class PagerView: NSView {
    static let gap: CGFloat = 30

    var pages: [PhotoPage] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            pages.forEach(strip.addSubview)
            needsLayout = true
        }
    }
    /// Asked to go to a page, by a swipe.
    var onPage: ((Int) -> Void)?

    private let strip = NSView()
    private var current = 0
    private var drag: CGFloat = 0
    private var swiping = false
    private var lastDelta: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(strip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var stride: CGFloat { bounds.width + Self.gap }

    override func layout() {
        super.layout()
        for (i, page) in pages.enumerated() {
            page.frame = CGRect(x: CGFloat(i) * stride, y: 0, width: bounds.width, height: bounds.height)
        }
        strip.frame = CGRect(x: offset, y: 0, width: CGFloat(max(pages.count, 1)) * stride, height: bounds.height)
    }

    private var offset: CGFloat { -CGFloat(current) * stride + drag }

    func show(_ index: Int, animated: Bool) {
        current = index
        settle(animated: animated)
    }

    /// Back in place at the current page.
    func settle(animated: Bool) {
        drag = 0
        let origin = CGPoint(x: offset, y: 0)
        guard animated else {
            needsLayout = true
            return strip.setFrameOrigin(origin)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            strip.animator().setFrameOrigin(origin)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // A trackpad's sideways swipe; momentum after it is spent.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) {
            swiping = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            drag = 0
        }
        guard swiping else { return }
        if event.phase.contains(.changed) {
            // Stiffer past the first and last.
            let edge = (current == 0 && drag + event.scrollingDeltaX > 0) || (current == pages.count - 1 && drag + event.scrollingDeltaX < 0)
            drag += event.scrollingDeltaX * (edge ? 0.3 : 1)
            lastDelta = event.scrollingDeltaX
            strip.setFrameOrigin(CGPoint(x: offset, y: 0))
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            swiping = false
            // Dragged left, the next photo; right, the one before.
            let flick = abs(lastDelta) > 12 && (lastDelta < 0) == (drag < 0)
            if event.phase.contains(.ended), drag != 0, abs(drag) > bounds.width / 5 || flick {
                onPage?(current + (drag < 0 ? 1 : -1))
            } else {
                settle(animated: true)
            }
        }
    }
}

/// One photo, fitted to the view and centred; zooms with a pinch and pans
/// with a drag. Until it's in, a spinner.
fileprivate final class PhotoPage: NSScrollView {
    private let photo = PhotoView()
    private let spinner = NSProgressIndicator()
    private let failed = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) ?? NSImage())

    var hasImage: Bool { photo.image != nil }

    var image: NSImage? {
        get { photo.image }
        set {
            photo.image = newValue
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            failed.isHidden = true
            fit()
        }
    }

    init() {
        super.init(frame: .zero)
        contentView = CentringClipView()
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        allowsMagnification = true
        minMagnification = 1
        maxMagnification = ImageViewer.maxZoom
        photo.imageScaling = .scaleProportionallyUpOrDown
        photo.animates = true
        documentView = photo
        for view in [spinner, failed] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        spinner.style = .spinning
        spinner.controlSize = .large
        spinner.startAnimation(nil)
        failed.contentTintColor = .secondaryLabelColor
        failed.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showFailed() {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        failed.isHidden = false
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fit()
    }

    /// Fitted to the view, no larger than its own size — at whatever zoom
    /// it's at, so the full photo coming in, or the window growing, keeps it.
    private func fit() {
        let bounds = contentSize
        guard let size = photo.image?.pixelSize, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            photo.frame = CGRect(origin: .zero, size: bounds)
            return
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height, 1)
        photo.frame = CGRect(origin: .zero, size: CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded()))
    }

    func resetZoom() {
        guard magnification != 1 else { return }
        animator().magnification = 1
    }

    func zoom(by factor: CGFloat) {
        let target = min(max(magnification * factor, minMagnification), maxMagnification)
        let centre = contentView.convert(CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY), to: photo)
        NSAnimationContext.runAnimationGroup { _ in
            animator().setMagnification(target, centeredAt: centre)
        }
    }

    var isZoomed: Bool { magnification > 1.001 }

    /// Not zoomed, a swipe is the pager's, to the next photo.
    override func scrollWheel(with event: NSEvent) {
        if isZoomed { super.scrollWheel(with: event) } else { nextResponder?.scrollWheel(with: event) }
    }
}

/// Keeps a photo smaller than the view in its middle.
private final class CentringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView?.frame else { return rect }
        if rect.width > document.width { rect.origin.x = (document.width - rect.width) / 2 }
        if rect.height > document.height { rect.origin.y = (document.height - rect.height) / 2 }
        return rect
    }
}

/// The photo itself: zoomed in, a hand that drags it about.
private final class PhotoView: NSImageView {
    private var page: PhotoPage? { enclosingScrollView as? PhotoPage }
    private var grabbed: NSPoint?

    override func resetCursorRects() {
        if page?.isZoomed == true { addCursorRect(visibleRect, cursor: .openHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard page?.isZoomed == true else { return super.mouseDown(with: event) }
        grabbed = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grabbed, let page, let clip = page.contentView as NSClipView? else { return }
        let point = event.locationInWindow
        let scale = page.magnification
        var origin = clip.bounds.origin
        origin.x -= (point.x - grabbed.x) / scale
        origin.y -= (point.y - grabbed.y) / scale
        clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: origin, size: clip.bounds.size)).origin)
        page.reflectScrolledClipView(clip)
        self.grabbed = point
    }

    override func mouseUp(with event: NSEvent) {
        guard grabbed != nil else { return super.mouseUp(with: event) }
        grabbed = nil
        NSCursor.pop()
        window?.invalidateCursorRects(for: self)
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        window?.invalidateCursorRects(for: self)
    }
}

private extension NSImage {
    /// Its size in pixels — what a photo's own size is — rather than in
    /// points at whatever resolution its file claims.
    var pixelSize: CGSize {
        guard let rep = representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
