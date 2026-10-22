import Foundation

/// The sites whose videos the plugin plays, each with its own search script:
/// which video is under the pointer, and the link yt-dlp looks it up by.
/// Everything after that is the same for every site. Listed in the plugin's
/// manifest, which Voyager reads too, to put each script in its site's pages.
///
/// A site's script is one JavaScript object whose `find(stack, x, y)` is
/// given the elements at the pointer (`x`, `y` in the viewport), top first,
/// and returns the video's `element` — a `<video>`, or a player or link
/// standing for one — with its `page` for yt-dlp, or a `file` that plays as
/// it is; or null — and the `video` whose time is the video's, when that
/// isn't the `<video>` in the element (null for none). An optional
/// `seek(time, page)` moves the site's player when a window closes, for a
/// player that ignores its video's time being set; it runs in the page's own
/// world. `web(url)`, `videoIn(el)` and `big(el)` are in scope.
enum MediaSites {
    typealias Site = PluginManifest.Site

    /// What a site's script names.
    enum Video {
        /// A page with a video on it, for yt-dlp.
        case page(URL)
        /// A video file, fetched as the page it was in would fetch it.
        case file(URL, referrer: URL?)

        var key: String {
            switch self {
            case .page(let url): "page:\(url.absoluteString)"
            case .file(let url, _): "file:\(url.absoluteString)"
            }
        }

        /// The page or file, as the page's script named it.
        var url: URL {
            switch self {
            case .page(let url), .file(let url, _): url
            }
        }
    }

    /// The plugin's manifest, from its resources.
    static let manifest: PluginManifest? = Bundle.main.url(forResource: "manifest", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(PluginManifest.self, from: $0) }

    static let sites: [Site] = (manifest?.triggers ?? []).flatMap(\.sites)

    /// The site for pages on `host`.
    static func site(for host: String?) -> Site? {
        guard let host else { return nil }
        return sites.first { $0.matches(host: host) }
    }
}
