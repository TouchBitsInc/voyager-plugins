import Foundation

/// How Voyager and its plugins talk. A plugin is an app of its own, outside
/// the App Store and its sandbox, doing what Voyager can't — the Media
/// Plugin plays and saves a page's videos. Voyager, sandboxed, only finds
/// the plugins installed, puts their site scripts in the pages they're for,
/// and hands them what those scripts catch.
///
/// - Voyager finds a plugin by its bundle ID, and reads its manifest and
///   site scripts from the app — or, where the sandbox can't read the app
///   (in ~/Applications), from the copy the plugin keeps in the shared
///   folder, the App Group's.
/// - A trigger — a click a site script took — goes to the plugin as a
///   request file in the shared folder, with the site's cookies, and the
///   plugin's URL naming it.
/// - The plugin answers with distributed notifications: a JSON event as the
///   notification's object, which reaches a sandboxed app (a user-info
///   dictionary wouldn't).
enum PluginProtocol {
    static let version = 1
    /// The folder both sides share. Team-prefixed: a sandboxed app may use
    /// it without a provisioning profile.
    static let appGroup = "8Z3UH5979Z.com.touchbits.voyager"
    /// The plugins Voyager knows of, by bundle ID, with their names for
    /// Settings while they're not installed.
    static let plugins: [(id: String, name: String)] = [
        ("com.touchbits.voyager.media-plugin", "Media Plugin"),
    ]
    static func isPlugin(_ bundleID: String?) -> Bool {
        plugins.contains { $0.id == bundleID }
    }

    /// What a plugin says back.
    static let eventName = Notification.Name("com.touchbits.voyager.plugin.event")
    static let manifestName = "manifest.json"

    static var sharedFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Where a plugin keeps a copy of its manifest and scripts, for Voyager.
    static func pluginFolder(_ id: String) -> URL? {
        sharedFolder?.appending(path: "Plugins/\(id)")
    }

    /// Where a request waits for its plugin. Its ID is a UUID — anything
    /// else, from a URL any app or page can open, names no file, so it
    /// can't reach outside the folder.
    static func requestFile(_ id: String) -> URL? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return sharedFolder?.appending(path: "Requests/\(uuid.uuidString).json")
    }

    /// Whether `host` is `domain` or under it: `m.x.com` is in `x.com`.
    static func host(_ host: String, isIn domain: String) -> Bool {
        let host = host.lowercased(), domain = domain.lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }
}

/// What a plugin is and what it takes, from its app's resources.
struct PluginManifest: Codable, Equatable {
    var id: String
    var name: String
    var protocolVersion: Int
    /// The plugin's version, filled in by the plugin in the copy it keeps
    /// in the shared folder.
    var version: String?
    /// Its URL scheme: `<scheme>://trigger?id=…`, `<scheme>://settings`.
    var scheme: String
    var triggers: [Trigger]

    struct Trigger: Codable, Equatable {
        /// `media.click`: a plain click on a page's media, taken from the
        /// page by the site's script.
        var kind: String
        /// `video`; `image` to come.
        var media: [String]
        var sites: [Site]
    }

    struct Site: Codable, Equatable {
        var name: String

        /// Whether pages on `host` are this site's.
        func matches(host: String) -> Bool {
            hosts.contains { PluginProtocol.host(host, isIn: $0) }
        }

        /// Domains it runs on, subdomains included.
        var hosts: [String]
        /// Its script, a file in the manifest's folder.
        var script: String
        /// Whether the plugin gets the site's cookies with a request, to see
        /// what the panel sees — protected tweets. Off where they cost more
        /// than they give: signed in, yt-dlp asks YouTube as its website
        /// does, which needs a JavaScript runtime to unlock any stream.
        var cookies: Bool
    }
}

/// A trigger, handed to the plugin.
struct PluginRequest: Codable {
    var id: String
    var kind: String
    /// A page with the media on it, or the media's own file.
    var page: String?
    var file: String?
    var referrer: String?
    var time: Double
    /// The media's size, as the page knew it; zero when it didn't.
    var width: Double
    var height: Double
    /// Where it was on screen, in screen points, to grow a window from.
    var frame: Frame?
    var cookies: [Cookie]
    /// The app that sent it, to give focus back to when the plugin hands
    /// the request back.
    var requester: String?

    struct Frame: Codable {
        var x, y, width, height: Double
    }

    struct Cookie: Codable {
        var name, value, domain, path: String
        var secure: Bool
        var expires: Double?
    }
}

/// What a plugin says back about a request.
struct PluginEvent: Codable {
    enum Kind: String, Codable {
        /// The plugin has it; no need to hand it back.
        case accepted
        /// The plugin can't do anything with it: the page carries on as if
        /// it had never been taken.
        case unhandled
        /// Done with — a player closed — at `time`.
        case closed
        /// The plugin started and put its manifest in the shared folder.
        case ready
    }

    var kind: Kind
    var plugin: String
    var request: String?
    var time: Double?

    var json: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    init(kind: Kind, plugin: String, request: String? = nil, time: Double? = nil) {
        self.kind = kind
        self.plugin = plugin
        self.request = request
        self.time = time
    }

    init?(json: String) {
        guard let event = try? JSONDecoder().decode(PluginEvent.self, from: Data(json.utf8)) else { return nil }
        self = event
    }
}

extension PluginRequest.Cookie {
    init(_ cookie: HTTPCookie) {
        self.init(name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
                  secure: cookie.isSecure, expires: cookie.expiresDate?.timeIntervalSince1970)
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if secure { properties[.secure] = "TRUE" }
        if let expires { properties[.expires] = Date(timeIntervalSince1970: expires) }
        return HTTPCookie(properties: properties)
    }
}

enum FileNames {
    /// `name.ext`, or `name 2.ext`, `name 3.ext`… — the first that's free.
    /// Path separators in the suggested name are dropped, so a server can't
    /// aim outside the folder.
    /// `taken`: destinations of downloads still running — their files may
    /// not exist yet, but the names are spoken for.
    static func uniqueDestination(for suggestedFilename: String, in directory: URL, taken: Set<URL> = []) -> URL {
        let cleaned = suggestedFilename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var filename = cleaned.isEmpty || cleaned.hasPrefix(".") ? "Download" + cleaned : cleaned
        // Room under the file system's 255-byte limit for " 99" and the
        // extension.
        let suffix = (filename as NSString).pathExtension
        var stem = (filename as NSString).deletingPathExtension
        while stem.utf8.count > 200 { stem.removeLast() }
        filename = suffix.isEmpty ? stem : "\(stem).\(suffix)"

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appending(path: filename)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) || taken.contains(candidate) {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appending(path: name)
            index += 1
        }
        return candidate
    }
}
