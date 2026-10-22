import AVFoundation
import Foundation
import VideoToolbox

/// Finds a video's playable stream with `yt-dlp` — it knows how YouTube, X,
/// Weibo and many more sites serve video. Why this is a plugin, outside the
/// App Store: a sandboxed app can't run it.
///
/// The plugin brings its own copy, one version, pinned in `tools.json` and
/// put in the app when it's built: a new yt-dlp is a new plugin. It's the
/// release unpacked as a folder, not the single-file one: that one unpacks
/// Python into a temporary folder on every run, nearly 4 seconds before it
/// does anything; the folder starts in a fifth of a second. The first run
/// takes as long while macOS checks it, so the plugin makes that run itself,
/// at launch.
@MainActor
@Observable
final class VideoPlugins {
    static let shared = VideoPlugins()

    /// What Settings shows about the tool.
    let name = "yt-dlp"
    let summary = "Finds the video stream on YouTube, X, Weibo and over a thousand other sites, so videos play in a window of their own."
    let homepage = URL(string: "https://github.com/yt-dlp/yt-dlp")!

    /// The bundled copy's version, as `tools.json` pins it.
    let version: String? = {
        guard let url = Bundle.main.url(forResource: "tools", withExtension: "json", subdirectory: "Tools"),
              let data = try? Data(contentsOf: url),
              let tools = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
        else { return nil }
        return tools["yt-dlp"]?["version"]
    }()

    /// The bundled program; nil in a build made without it.
    let executable: URL? = {
        let program = Bundle.main.resourceURL?.appending(path: "Tools/yt-dlp/yt-dlp_macos")
        return program.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }()

    var isInstalled: Bool { executable != nil }

    /// Streams found, by page or file, each kept until its address stops
    /// working — YouTube's say when, in the address — less five minutes,
    /// or for an hour: a video opened again starts at once.
    private var found: [String: (task: Task<PlayableVideo?, Never>, expires: Date?)] = [:]

    private init() {
        // Its first run, for macOS's check of it, made now rather than on
        // the first video.
        if let executable {
            Task { _ = try? await Self.run(executable, ["--version"], timeout: 60) }
        }
    }

    // MARK: - Finding Videos

    /// A stream AVFoundation can play for `video`, or nil. A page goes to
    /// yt-dlp — only a page on one of the sites, over HTTPS, as a link in a
    /// post can point anywhere — with the site's cookies where it takes
    /// them, so what the panel can see it can see; a file is played as it
    /// is, fetched as the page would fetch it. Nothing found isn't kept: a
    /// second click asks again.
    func playable(_ video: MediaSites.Video, cookies jar: [HTTPCookie]) async -> PlayableVideo? {
        let key = video.key
        // A lookup whose window closed before it was done is being stopped:
        // asked again, it starts over.
        if let entry = found[key], !entry.task.isCancelled, entry.expires.map({ $0 > Date() }) ?? true {
            return await entry.task.value
        }
        // Gone stale, every one: kept streams hold their players' assets.
        found = found.filter { $0.value.expires.map { $0 > Date() } ?? true }
        let executable = executable
        let task = Task { @MainActor () -> PlayableVideo? in
            switch video {
            case .file(let url, let referrer):
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
                var headers = HTTPCookie.requestHeaderFields(with: Self.cookies(jar, for: url))
                if let referrer { headers["Referer"] = referrer.absoluteString }
                let video = await PlayableVideo.check(url: url, headers: headers, size: nil, source: url.absoluteString)
                video?.saving = .file(url, headers: headers)
                return video
            case .page(let url):
                guard url.scheme?.lowercased() == "https", MediaSites.site(for: url.host()) != nil,
                      let executable
                else { return nil }
                return await Self.lookUp(url, with: executable, cookies: jar)
            }
        }
        found[key] = (task, nil)
        // A window closed before the stream was found stops looking — and
        // stops yt-dlp — rather than leaving it to run on.
        let video = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard found[key]?.task == task else { return video }
        if let video {
            let latest = Date().addingTimeInterval(6 * 3600)
            let expires = video.expires.map { min($0.addingTimeInterval(-300), latest) } ?? Date().addingTimeInterval(3600)
            found[key]?.expires = expires
        } else {
            found[key] = nil
        }
        return video
    }

    /// yt-dlp's formats for the page, and the best AVFoundation plays:
    /// one with both picture and sound, or — when they're taller, as
    /// YouTube's are — its HLS pictures joined to its HLS sound.
    private static func lookUp(_ page: URL, with executable: URL, cookies: [HTTPCookie]) async -> PlayableVideo? {
        let site = MediaSites.site(for: page.host())
        let cookieFile = cookieFile(cookies, for: site)
        defer { try? FileManager.default.removeItem(at: cookieFile) }
        // Every format is wanted, not yt-dlp's pick, and none at all is an
        // answer rather than an error.
        let arguments = ["-j", "--no-warnings", "--no-playlist", "--ignore-no-formats-error",
                         "--cookies", cookieFile.path] + target(page)
        let started = Date()
        let data: Data
        do {
            data = try await run(executable, arguments, timeout: 45)
        } catch {
            Log.media.notice("yt-dlp failed for \(page.absoluteString, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return nil
        }
        // One line per video; a tweet with several, asked for as a whole,
        // gives several — the first is it.
        let first = data.split(separator: UInt8(ascii: "\n")).first.map { Data($0) } ?? data
        guard let info = try? JSONDecoder().decode(YTDLPInfo.self, from: first) else {
            Log.media.notice("yt-dlp gave no formats for \(page.absoluteString, privacy: .private)")
            return nil
        }
        let video = await choose(from: info.formats ?? [])
        video?.saving = saving(page, title: info.title, formats: info.formats ?? [])
        let took = String(format: "%.1f", -started.timeIntervalSinceNow)
        let result = video.map { $0.asset.url.scheme ?? "?" } ?? "nothing playable"
        Log.media.notice("Looked up \(page.absoluteString, privacy: .private) in \(took, privacy: .public)s with\(site?.cookies == true ? "" : "out", privacy: .public) cookies: \(info.formats?.count ?? 0) formats, \(result, privacy: .public)")
        return video
    }

    /// The page for yt-dlp; with `#item=N`, the Nth video of the several
    /// it finds there — a tweet's own videos, then its quoted tweet's.
    private static func target(_ page: URL) -> [String] {
        guard let item = page.fragment?.firstMatch(of: /^item=(\d+)$/)?.1,
              var parts = URLComponents(url: page, resolvingAgainstBaseURL: false)
        else { return [page.absoluteString] }
        parts.fragment = nil
        return ["--playlist-items", String(item), parts.url?.absoluteString ?? page.absoluteString]
    }

    /// Every sound track in `formats` — the original, and each language
    /// it's dubbed into — in the better of its versions, the one to play
    /// first leading.
    private static func soundTracks(in formats: [YTDLPFormat]) -> [YTDLPFormat] {
        Dictionary(grouping: formats.filter { $0.vcodec == "none" && $0.acodec != "none" }) {
            $0.language ?? $0.format_note ?? ""
        }.values
            .compactMap { $0.max { $0.soundRank < $1.soundRank } }
            .sorted { $0.soundRank > $1.soundRank }
    }

    private static func choose(from formats: [YTDLPFormat]) async -> PlayableVideo? {
        let playableCodec = { (codec: String?) in
            guard let codec, codec != "none" else { return codec == nil }
            return ["avc1", "h264", "hvc1", "hev1", "mp4v"].contains { codec.hasPrefix($0) }
        }
        let byHeight = { (a: YTDLPFormat, b: YTDLPFormat) in (a.height ?? 0, a.tbr ?? 0) < (b.height ?? 0, b.tbr ?? 0) }
        let streamable = formats.filter { $0.isHLS || $0.ext == "mp4" || $0.ext == "m4v" || $0.ext == "mov" }

        // Picture and sound apart, both HLS: one master playlist joins them,
        // its pictures for AVPlayer to pick from as the line and the window
        // allow. VP9 is YouTube's only way past 1080p, and every Apple
        // silicon Mac plays it — but AVPlayer keeps to the codec it starts
        // with, so it's all VP9 if there's VP9, else H.264. Not YouTube's
        // HDR10 VP9: AVPlayer plays it on its own, but not from a master
        // playlist — any, with or without CODECS or VIDEO-RANGE — and one
        // is how its sound is joined to it.
        let pictures = formats
            .filter { $0.isHLS && $0.acodec == "none" && $0.vcodec != nil && !$0.isHDR && (playableCodec($0.vcodec) || $0.vcodec?.hasPrefix("vp09") == true) }
            .filter { PlayableVideo.quality(of: $0.size) <= 2160 }
        // Every sound track — the original, and each language it's dubbed
        // into — in the better of its versions; the one to play first.
        let sounds = soundTracks(in: formats.filter { $0.isHLS })
        let sound = sounds.first

        // Picture and sound together.
        let muxed = streamable
            .filter { $0.vcodec != "none" && $0.acodec != "none" && playableCodec($0.vcodec) }
            .sorted(by: byHeight)
        func together() async -> PlayableVideo? {
            for format in muxed.reversed().prefix(3) {
                guard let url = URL(string: format.url) else { continue }
                let size = format.size
                if let video = await PlayableVideo.check(url: url, headers: format.http_headers ?? [:], size: size, source: format.url) {
                    video.streams = [format.url: PlayableVideo.Stream(format)]
                    return video
                }
            }
            return nil
        }
        func joined() async -> PlayableVideo? {
            guard let sound else { return nil }
            let isVP9 = { (format: YTDLPFormat) in format.vcodec?.hasPrefix("vp09") == true }
            for set in [pictures.filter(isVP9), pictures.filter { !isVP9($0) }] {
                guard let tallest = set.max(by: byHeight) else { continue }
                let size = tallest.size
                if let video = await PlayableVideo.joining(pictures: set, sound: sound, others: sounds.filter { $0.url != sound.url }, size: size) {
                    return video
                }
            }
            return nil
        }
        // The taller first, and the other if it won't play.
        let joinedIsTaller = (pictures.map { $0.height ?? 0 }.max() ?? 0) > (muxed.last?.height ?? 0)
        if joinedIsTaller {
            if let video = await joined() { return video }
            return await together()
        }
        if let video = await together() { return video }
        return await joined()
    }

    // MARK: - Saving

    /// The ways to save a video: each size and codec a Mac plays — H.264,
    /// HEVC, and AV1 where the Mac decodes it in hardware; not VP9, which
    /// YouTube only has as WebM — with picture and sound together, as X's
    /// and Weibo's are, or a picture to join to a sound track. Whole files
    /// only: streams in pieces (HLS) need a tool yt-dlp doesn't bring to put
    /// back together.
    private static func saving(_ page: URL, title: String?, formats: [YTDLPFormat]) -> PlayableVideo.Saving? {
        let whole = formats.filter { $0.protocol_ == "https" && ["mp4", "m4a", "m4v", "mov"].contains($0.ext ?? "") }
        let tracks = soundTracks(in: whole)
        // By language, for the track playing; one without isn't picked so.
        let sounds = Dictionary(tracks.compactMap { track in track.language.flatMap { language in track.format_id.map { (language, $0) } } }) { first, _ in first }
        let sound = tracks.first?.format_id
        let decodesAV1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        let codecName = { (codec: String?) -> String? in
            guard let codec else { return "H.264" }
            if codec.hasPrefix("avc1") || codec.hasPrefix("h264") { return "H.264" }
            if codec.hasPrefix("hvc1") || codec.hasPrefix("hev1") { return "HEVC" }
            if codec.hasPrefix("av01"), decodesAV1 { return "AV1" }
            return nil
        }
        // The best of each size and codec.
        var best: [String: (choice: PlayableVideo.SaveChoice, bitrate: Double)] = [:]
        for format in whole where format.vcodec != "none" {
            let hasSound = format.acodec != "none"
            guard let id = format.format_id, let name = codecName(format.vcodec), hasSound || sound != nil else { continue }
            let codec = format.isHDR ? "\(name) HDR" : name
            // 0 when yt-dlp doesn't say: "Original". Up to 8K.
            let size = PlayableVideo.quality(of: format.size)
            guard size <= 4320 else { continue }
            let choice = PlayableVideo.SaveChoice(format: id, hasSound: hasSound, size: size, codec: codec)
            let key = "\(size) \(codec)"
            if (format.tbr ?? 0) >= best[key]?.bitrate ?? -1 { best[key] = (choice, format.tbr ?? 0) }
        }
        // Tallest first; of a size, the one that plays anywhere first.
        // H.264, then HEVC, then AV1; SDR before HDR. The format settles a
        // tie, so the order is the same every time.
        let rank = { (choice: PlayableVideo.SaveChoice) -> Int in
            let codec = ["H.264", "HEVC", "AV1"].firstIndex { choice.codec.hasPrefix($0) } ?? 3
            return codec * 2 + (choice.codec.hasSuffix(" HDR") ? 1 : 0)
        }
        let choices = best.values.map(\.choice).sorted {
            ($1.size, rank($0), $0.format) < ($0.size, rank($1), $1.format)
        }
        guard !choices.isEmpty else { return nil }
        return .formats(page: page, title: title, choices: choices, sounds: sounds, sound: sound)
    }

    /// Saves `video` to `destination` — as `choice`, or the first of its
    /// choices, with the sound track in `language` where it's joined to one
    /// — telling `progress` how far it's got, from 0 to 1.
    func save(
        _ video: PlayableVideo,
        as choice: PlayableVideo.SaveChoice? = nil,
        language: String? = nil,
        cookies jar: [HTTPCookie],
        to destination: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard let saving = video.saving else { throw SaveError.notSaveable }
        let work = FileManager.default.temporaryDirectory.appending(path: "voyager-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        switch saving {
        case .file(let url, let headers):
            var request = URLRequest(url: url)
            for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
            let (file, response) = try await URLSession.shared.download(for: request, delegate: DownloadProgress { done in
                Task { @MainActor in progress(done) }
            })
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.moveItem(at: file, to: destination)
        case .formats(let page, _, let choices, let sounds, let sound):
            guard let executable, let choice = choice ?? choices.first else { throw SaveError.notSaveable }
            let ids: [String]
            if choice.hasSound {
                ids = [choice.format]
            } else if let sound = language.flatMap({ sounds[$0] }) ?? sound {
                ids = [choice.format, sound]
            } else {
                throw SaveError.notSaveable
            }
            let cookieFile = Self.cookieFile(jar, for: MediaSites.site(for: page.host()))
            defer { try? FileManager.default.removeItem(at: cookieFile) }
            var parts: [URL] = []
            for (index, id) in ids.enumerated() {
                let arguments = ["-f", id, "-o", work.appending(path: "part\(index).%(ext)s").path,
                                 "--no-playlist", "--no-warnings", "--newline", "--no-part",
                                 "--progress-template", "download:%(progress._percent_str)s",
                                 "--cookies", cookieFile.path] + Self.target(page)
                _ = try await Self.run(executable, arguments, timeout: 3600) { line in
                    guard let percent = Double(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")) else { return }
                    let done = (Double(index) + percent / 100) / Double(ids.count)
                    Task { @MainActor in progress(done) }
                }
                guard let part = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                    .first(where: { $0.lastPathComponent.hasPrefix("part\(index).") })
                else { throw SaveError.missingPart }
                parts.append(part)
            }
            if parts.count == 1 {
                try FileManager.default.moveItem(at: parts[0], to: destination)
            } else {
                do {
                    try await VideoJoin.join(picture: parts[0], sound: parts[1], into: destination)
                } catch {
                    throw SaveError.joinFailed
                }
            }
        }
        progress(1)
    }

    enum SaveError: LocalizedError {
        case notSaveable, missingPart, joinFailed

        var errorDescription: String? {
            switch self {
            case .notSaveable: "This video can\u{2019}t be saved."
            case .missingPart: "yt-dlp didn\u{2019}t save the video."
            case .joinFailed: "The picture and sound couldn\u{2019}t be put together."
            }
        }
    }

    // MARK: - Running

    /// Runs a tool to its end, with what it printed; `onLine` hears each
    /// line as it comes.
    private static func run(
        _ executable: URL,
        _ arguments: [String],
        timeout: TimeInterval,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> Data {
        // Cancelled, it's stopped — a window closed mid-lookup doesn't leave
        // yt-dlp running on.
        let running = ProcessBox()
        return try await withTaskCancellationHandler {
            try await run(executable, arguments, timeout: timeout, onLine: onLine, in: running)
        } onCancel: {
            running.terminate()
        }
    }

    private static func run(
        _ executable: URL,
        _ arguments: [String],
        timeout: TimeInterval,
        onLine: (@Sendable (String) -> Void)?,
        in running: ProcessBox
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            do {
                guard try running.run(process) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
            } catch {
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
            // Both pipes read to their end on their own threads — one left
            // unread fills up and stalls the tool — and only then is it done.
            let said = DataBox()
            let errorsRead = DispatchGroup()
            errorsRead.enter()
            DispatchQueue.global().async {
                said.append(errors.fileHandleForReading.readDataToEndOfFile())
                errorsRead.leave()
            }
            DispatchQueue.global().async {
                var data = Data()
                // Lines whole, though a read can end mid-line.
                var heard = 0
                while case let chunk = output.fileHandleForReading.availableData, !chunk.isEmpty {
                    data.append(chunk)
                    guard let onLine, let end = data.lastIndex(of: UInt8(ascii: "\n")), end >= heard else { continue }
                    data[heard..<end].split(separator: UInt8(ascii: "\n")).forEach { onLine(String(decoding: $0, as: UTF8.self)) }
                    heard = end + 1
                }
                process.waitUntilExit()
                errorsRead.wait()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    // The last of what it said, for the log.
                    let message = String(decoding: said.data.suffix(600), as: UTF8.self)
                    continuation.resume(throwing: RunError(status: process.terminationStatus, message: message))
                }
            }
        }
    }

    /// A file of `site`'s cookies, on any of its domains, for yt-dlp —
    /// empty for a site that's better off without them — for the caller to
    /// delete.
    private static func cookieFile(_ cookies: [HTTPCookie], for site: MediaSites.Site?) -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "voyager-cookies-\(UUID().uuidString).txt")
        let hosts = site?.cookies == true ? site?.hosts ?? [] : []
        try? netscapeCookies(cookies.filter { cookie in
            hosts.contains { isIn(domainOf(cookie), $0) }
        }).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func isIn(_ host: String, _ domain: String) -> Bool {
        PluginProtocol.host(host, isIn: domain)
    }

    private static func domainOf(_ cookie: HTTPCookie) -> String {
        cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// The site's cookies in the file format yt-dlp reads.
    private static func netscapeCookies(_ cookies: [HTTPCookie]) -> String {
        var lines = ["# Netscape HTTP Cookie File"]
        for cookie in cookies {
            let subdomains = cookie.domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let expiry = Int(cookie.expiresDate?.timeIntervalSince1970 ?? 0)
            lines.append([cookie.domain, subdomains, cookie.path, cookie.isSecure ? "TRUE" : "FALSE",
                          String(expiry), cookie.name, cookie.value].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The site's cookies that a file's host would be sent.
    private static func cookies(_ cookies: [HTTPCookie], for url: URL) -> [HTTPCookie] {
        guard let host = url.host()?.lowercased() else { return [] }
        return cookies.filter { cookie in
            isIn(host, domainOf(cookie))
                && (!cookie.isSecure || url.scheme == "https")
                && url.path().hasPrefix(cookie.path)
        }
    }
}

/// A tool that exited with an error, and the end of what it said.
private struct RunError: LocalizedError {
    var status: Int32
    var message: String

    var errorDescription: String? { "exit \(status): \(message)" }
}

/// What `yt-dlp -j` says about a page, as far as playing it goes.
private struct YTDLPInfo: Decodable {
    var title: String?
    var formats: [YTDLPFormat]?

    enum CodingKeys: String, CodingKey { case title, formats }

    /// Formats it can't use — no address, as some DRM'd or pieced ones
    /// have — are skipped, not a failure of the whole page.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decode(String.self, forKey: .title)
        guard var list = try? container.nestedUnkeyedContainer(forKey: .formats) else { return }
        var formats: [YTDLPFormat] = []
        while !list.isAtEnd {
            if let format = try? list.decode(YTDLPFormat.self) {
                formats.append(format)
            } else {
                _ = try? list.decode(Skipped.self)
            }
        }
        self.formats = formats
    }

    private struct Skipped: Decodable {}
}

private struct YTDLPFormat: Decodable {
    var url: String
    var format_id: String?
    var ext: String?
    var protocol_: String?
    var vcodec: String?
    var acodec: String?
    var width: Double?
    var height: Double?
    var tbr: Double?
    var abr: Double?
    var fps: Double?
    var dynamic_range: String?
    var http_headers: [String: String]?

    var language: String?
    var language_preference: Int?
    var format_note: String?

    var isHLS: Bool { protocol_?.hasPrefix("m3u8") == true }

    /// HDR10, HLG or Dolby Vision, as yt-dlp says.
    var isHDR: Bool { dynamic_range.map { $0 != "SDR" } ?? false }

    var size: CGSize? {
        width.flatMap { w in height.map { CGSize(width: w, height: $0) } }
    }

    /// Which sound to play: the video's own before YouTube's AI dubs ("…
    /// dubbed-auto"), the original language — yt-dlp prefers it, 10 — and
    /// then the better of a "low" and "high" pair — named so, or YouTube's
    /// 234 over its 233 — and the higher bitrate.
    var soundRank: (Int, Int, Int, Double) {
        let note = format_note?.lowercased() ?? ""
        return (
            note.contains("dubbed") ? 0 : 1,
            language_preference ?? 0,
            note.contains("high") || format_id == "234" || format_id?.hasPrefix("234-") == true ? 1 : 0,
            abr ?? tbr ?? 0
        )
    }

    /// A sound track's name, for the player's Audio menu: its language,
    /// and whether it's the original or a dub.
    var trackName: String {
        let note = format_note?.lowercased() ?? ""
        let language = language.flatMap { Locale.current.localizedString(forIdentifier: $0) }
            ?? format_note?.components(separatedBy: " - ").first
            ?? "Sound"
        if note.contains("original") { return "\(language) \u{2013} Original" }
        if note.contains("dubbed") { return "\(language) \u{2013} Dubbed" }
        return language
    }

    enum CodingKeys: String, CodingKey {
        case url, format_id, ext, vcodec, acodec, width, height, tbr, abr, fps, dynamic_range, http_headers, language, language_preference, format_note
        case protocol_ = "protocol"
    }
}

/// How far a file's download has got, as its task says.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    /// The last whole percent told: a large file's progress changes far
    /// more often than the pie can show.
    private var told = -1
    private let lock = NSLock()

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.changed(to: progress.fractionCompleted)
        }
    }

    private func changed(to fraction: Double) {
        let percent = Int(fraction * 100)
        lock.lock()
        let isNew = percent != told
        told = percent
        lock.unlock()
        if isNew { onProgress(fraction) }
    }
}

/// A running tool, for cancellation to stop from any thread — or to stop
/// before it starts.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// Starts `process`, held to stop later; false, and not started, if
    /// it's already been cancelled. Started under the lock, so a stop
    /// can't fall between the check and the start.
    func run(_ process: Process) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        try process.run()
        return true
    }

    func terminate() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process?.isRunning == true { process?.terminate() }
    }
}

/// Output gathered from a process's pipe, off the main thread.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock(); buffer.append(data); lock.unlock()
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}

// MARK: - Playable Video

/// A video ready for AVPlayer: its asset, its size when known, and — for
/// picture and sound joined in a playlist of Voyager's — what serves that
/// playlist, kept alive as long as the asset.
final class PlayableVideo: @unchecked Sendable {
    let asset: AVURLAsset
    let size: CGSize?
    /// When the stream's address stops working, if it says.
    let expires: Date?
    /// How it's saved, when it can be.
    var saving: Saving?
    /// What each stream is, by its address — as yt-dlp said, for the video
    /// info — and the sound joined to them. AVPlayer doesn't say which
    /// codec an HLS stream is, but does say which stream it's playing.
    fileprivate(set) var streams: [String: Stream] = [:]
    /// The sound tracks, by language — as AVPlayer's audio options have
    /// them, in `extendedLanguageTag`.
    fileprivate(set) var sounds: [String: Stream] = [:]
    /// The sound it starts with: the original.
    fileprivate(set) var firstSound: Stream?
    private let playlist: JoinedPlaylist?

    struct Stream: Sendable {
        /// As yt-dlp names it: "vp09.00.51.08", "avc1.640028", "mp4a.40.2".
        var codec: String?
        var size: CGSize?
        var fps: Double?
        /// In kbit/s.
        var bitrate: Double?
        var language: String?
        var isHLS: Bool
        /// A sound track's name: its language, and whether it's the
        /// original or a dub.
        var name: String?

        fileprivate init(_ format: YTDLPFormat) {
            codec = format.vcodec.flatMap { $0 == "none" ? nil : $0 } ?? format.acodec
            size = format.size
            fps = format.fps
            bitrate = format.tbr ?? format.abr
            language = format.language
            isHLS = format.isHLS
            name = format.vcodec == "none" ? format.trackName : nil
        }
    }

    /// A picture size's name, as YouTube names them: "1080p" is 1080 tall
    /// at 16:9 — or as wide as that, for a wider picture (3840×1920 is
    /// 2160p, 4K), or as narrow, for a portrait one (1080×1920 is 1080p).
    /// 0 for none.
    static func quality(of size: CGSize?) -> Int {
        guard let size else { return 0 }
        let short = min(size.width, size.height), long = max(size.width, size.height)
        return Int(max(short, long * 9 / 16).rounded())
    }

    /// "1080p", "2160p (4K)", "4320p (8K)".
    static func qualityName(_ quality: Int) -> String {
        quality >= 4320 ? "\(quality)p (8K)" : quality >= 2160 ? "\(quality)p (4K)" : "\(quality)p"
    }

    /// Whether it's picture and sound joined in a playlist of Voyager's.
    var isJoined: Bool { playlist != nil }

    enum Saving {
        /// A file, fetched as the page would fetch it.
        case file(URL, headers: [String: String])
        /// yt-dlp's formats of the page: the `choices`, best first, and its
        /// sound tracks' formats by language, `sound` the original's.
        /// `title` names the file.
        case formats(page: URL, title: String?, choices: [SaveChoice], sounds: [String: String], sound: String?)

        /// A name for the saved file.
        var filename: String {
            switch self {
            case .file(let url, _): url.lastPathComponent.isEmpty ? "Video.mp4" : url.lastPathComponent
            case .formats(_, let title, _, _, _): "\(title ?? "Video").mp4"
            }
        }

        /// The sizes and codecs to pick from; none for a file.
        var choices: [SaveChoice] {
            if case .formats(_, _, let choices, _, _) = self { return choices }
            return []
        }
    }

    /// A size and codec a video can be saved in.
    struct SaveChoice: Sendable {
        /// yt-dlp's format.
        var format: String
        /// Whether it has its sound with it, or is joined to a sound track.
        var hasSound: Bool
        /// Its shorter side, as sizes are named: 1080 for 1080p.
        var size: Int
        var codec: String

        /// "2160p (4K) · AV1"; "Original · H.264" when its size isn't known.
        var title: String {
            let size = size == 0 ? String(localized: "Original") : PlayableVideo.qualityName(size)
            return "\(size) \u{00B7} \(codec)"
        }
    }

    /// `source` is the stream's address as the site gave it, which may say
    /// when it expires (YouTube's do: `expire=…` or `/expire/…/`).
    private init(asset: AVURLAsset, size: CGSize?, source: String, playlist: JoinedPlaylist? = nil) {
        self.asset = asset
        self.size = size
        self.playlist = playlist
        let stamp = source.firstMatch(of: /expire[=\/](\d{9,})/).flatMap { TimeInterval($0.1) }
        expires = stamp.map(Date.init(timeIntervalSince1970:))
    }

    /// `url`, if AVFoundation says it can play it.
    static func check(url: URL, headers: [String: String], size: CGSize?, source: String) async -> PlayableVideo? {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        guard (try? await asset.load(.isPlayable)) == true else { return nil }
        return PlayableVideo(asset: asset, size: size, source: source)
    }

    /// An HLS master playlist naming `pictures` as the streams and `sound`
    /// as their audio, with `others` to switch to, served to AVPlayer from
    /// memory.
    fileprivate static func joining(pictures: [YTDLPFormat], sound: YTDLPFormat, others: [YTDLPFormat], size: CGSize?) async -> PlayableVideo? {
        let variants = pictures.map { picture in
            var info = "BANDWIDTH=\(Int(((picture.tbr ?? 3000) + (sound.tbr ?? 128)) * 1000))"
            // A VP9 picture named as such isn't opened at all: left unnamed,
            // AVPlayer finds out for itself, and plays it.
            if let vcodec = picture.vcodec, !vcodec.hasPrefix("vp09") { info += ",CODECS=\"\(vcodec),\(sound.acodec ?? "mp4a.40.2")\"" }
            if let width = picture.width, let height = picture.height { info += ",RESOLUTION=\(Int(width))x\(Int(height))" }
            return "#EXT-X-STREAM-INF:\(info),AUDIO=\"sound\"\n\(picture.url)"
        }
        // Only the first is picked by itself: the others — dubs, mostly —
        // never on their own, even in the language the Mac is set to.
        let tracks = [sound] + others.sorted { $0.trackName < $1.trackName }
        var names: Set<String> = []
        let renditions = tracks.map { track in
            var name = track.trackName.replacingOccurrences(of: "\"", with: "'")
            while names.contains(name) { name += " " }
            names.insert(name)
            let first = track.url == sound.url ? "YES" : "NO"
            let language = track.language.map { "LANGUAGE=\"\($0)\"," } ?? ""
            return "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"sound\",NAME=\"\(name)\",\(language)DEFAULT=\(first),AUTOSELECT=\(first),URI=\"\(track.url)\""
        }
        let text = """
            #EXTM3U
            #EXT-X-INDEPENDENT-SEGMENTS
            \(renditions.joined(separator: "\n"))
            \(variants.joined(separator: "\n"))

            """
        let playlist = JoinedPlaylist(text: text)
        let asset = AVURLAsset(url: URL(string: "\(JoinedPlaylist.scheme)://playlist.m3u8")!, options: [
            "AVURLAssetHTTPHeaderFieldsKey": pictures.first?.http_headers ?? [:],
        ])
        asset.resourceLoader.setDelegate(playlist, queue: JoinedPlaylist.queue)
        guard (try? await asset.load(.isPlayable)) == true else { return nil }
        let video = PlayableVideo(asset: asset, size: size, source: pictures.first?.url ?? "", playlist: playlist)
        video.streams = Dictionary(pictures.map { ($0.url, Stream($0)) }) { first, _ in first }
        video.firstSound = Stream(sound)
        video.sounds = Dictionary(tracks.compactMap { track in track.language.map { ($0, Stream(track)) } }) { first, _ in first }
        return video
    }
}

/// Answers AVPlayer's request for a joined master playlist; the streams it
/// names are fetched by AVPlayer itself.
private final class JoinedPlaylist: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "voyager-hls"
    static let queue = DispatchQueue(label: "Voyager.JoinedPlaylist")

    private let data: Data

    init(text: String) {
        data = Data(text.utf8)
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard loadingRequest.request.url?.scheme == Self.scheme else { return false }
        loadingRequest.contentInformationRequest?.contentType = "public.m3u-playlist"
        loadingRequest.contentInformationRequest?.contentLength = Int64(data.count)
        loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = false
        loadingRequest.dataRequest?.respond(with: data)
        loadingRequest.finishLoading()
        return true
    }
}
