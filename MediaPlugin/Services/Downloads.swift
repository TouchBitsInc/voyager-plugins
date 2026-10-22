import AppKit

/// Where saved videos go: the folder the settings name — Downloads, unless
/// another's chosen — under a name that's free, announced as a browser's
/// download is: the Downloads stack in the Dock bounces.
@MainActor
final class Downloads {
    static let shared = Downloads()

    /// Names given out to files still being saved, so two saves at once
    /// don't get the same one.
    private var reserved: Set<URL> = []

    /// Whether a save is under way, so the plugin stays until it's done.
    var isBusy: Bool { !reserved.isEmpty }
    /// Told when the last save in progress ends.
    var onIdle: (() -> Void)?

    /// A free place in the Downloads folder for a file named `name`, held
    /// until `saved` or `failed`.
    func destination(for name: String) -> URL {
        let destination = FileNames.uniqueDestination(for: name, in: PluginSettings.shared.downloadFolder, taken: reserved)
        reserved.insert(destination)
        return destination
    }

    func saved(_ file: URL) {
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: file.path)
        done(file)
    }

    /// Saving failed, for `reason`: what was saved of it goes, and the
    /// user hears why.
    func failed(_ file: URL, reason: String) {
        Log.media.error("Saving failed (\(file.lastPathComponent, privacy: .private)): \(reason, privacy: .public)")
        try? FileManager.default.removeItem(at: file)
        let alert = NSAlert()
        alert.messageText = String(localized: "\u{201C}\(file.deletingPathExtension().lastPathComponent)\u{201D} couldn\u{2019}t be saved")
        alert.informativeText = reason
        NSApp.activate()
        alert.runModal()
        // Done once it's been read: the plugin doesn't quit with it open.
        done(file)
    }

    private func done(_ file: URL) {
        reserved.remove(file)
        if reserved.isEmpty { onIdle?() }
    }
}
