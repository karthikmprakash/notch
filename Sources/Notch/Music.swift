import AppKit
import SwiftUI

// MARK: - Music (Spotify / Apple Music via AppleScript)

@MainActor
final class MusicService: ObservableObject {
    enum Player: String, CaseIterable {
        case spotify = "Spotify"
        case music = "Music"

        var bundleID: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music: return "com.apple.Music"
            }
        }

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
    }

    struct Track: Equatable {
        var player: Player
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        /// Spotify exposes the cover as a URL; Music hands over the image data.
        var artworkURL: String?
    }

    enum Status: Equatable {
        case noPlayer
        case playing
        case paused
        /// Apple Events refused — the user said no to the Automation prompt.
        case automationDenied
    }

    @Published private(set) var track: Track?
    @Published private(set) var status: Status = .noPlayer
    @Published private(set) var artwork: NSImage?
    @Published private(set) var hasLyricsTile = false

    /// Position is polled once a second and interpolated in between, so the
    /// progress bar moves smoothly without hammering AppleScript.
    private var tickPosition: TimeInterval = 0
    private var tickDate = Date()
    private var timer: Timer?
    private var artworkKey: String?
    private let queue = DispatchQueue(label: "dev.kmp.notch.music")
    private var fetchingArtwork = false

    var isPlaying: Bool { status == .playing }
    var isActive: Bool { status != .noPlayer }

    /// Interpolated playback position.
    var position: TimeInterval {
        guard status == .playing else { return tickPosition }
        let elapsed = Date().timeIntervalSince(tickDate)
        let maxDuration = track?.duration ?? 0
        let value = tickPosition + elapsed
        return maxDuration > 0 ? min(value, maxDuration) : value
    }

    var progress: Double {
        guard let duration = track?.duration, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    // MARK: Polling

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Called when the music tile is hidden: stop touching the players entirely.
    func stop() {
        timer?.invalidate()
        timer = nil
        track = nil
        artwork = nil
        artworkKey = nil
        status = .noPlayer
    }

    private func poll() {
        // Never ask an app that is not running: AppleScript would launch it.
        let player: Player? = Player.allCases.first(where: { $0.isRunning })
        guard let player else {
            if status != .noPlayer {
                status = .noPlayer
                track = nil
                artwork = nil
            }
            return
        }
        queue.async { [weak self] in
            let script = player == .spotify ? Self.spotifyScript : Self.musicScript
            let result = Self.run(script)
            guard let self else { return }
            Task { @MainActor in self.apply(result, player: player) }
        }
    }

    private func apply(_ result: Result<[String], Error>, player: Player) {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            // -1743: not authorised to send Apple events.
            if nsError.code == -1743 {
                status = .automationDenied
                track = nil
            }
            return
        case .success(let fields):
            guard fields.count >= 6 else {
                if status != .noPlayer {
                    status = .noPlayer
                    track = nil
                    artwork = nil
                }
                return
            }
            let state = fields[0].lowercased()
            let duration = Double(fields[4]) ?? 0
            track = Track(
                player: player,
                title: fields[1],
                artist: fields[2],
                album: fields[3],
                duration: player == .spotify ? duration / 1000 : duration,
                artworkURL: fields.count > 6 ? fields[6] : nil
            )
            tickPosition = Double(fields[5]) ?? 0
            tickDate = Date()
            status = state == "playing" ? .playing : .paused
            updateArtwork(for: track)
        }
    }

    // MARK: Artwork

    private func updateArtwork(for track: Track?) {
        guard let track else { return }
        let key = "\(track.player.rawValue)|\(track.title)|\(track.artist)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil

        // Music.app: read the image data locally.
        if track.player == .music {
            queue.async { [weak self] in
                let data = Self.runArtworkData()
                guard let self else { return }
                Task { @MainActor in self.setArtwork(data: data) }
            }
            return
        }

        // Spotify: cached file first, then the URL from AppleScript.
        let cached = AppPaths.artwork.appendingPathComponent(cacheKey(key) + ".img")
        if let data = try? Data(contentsOf: cached) {
            setArtwork(data: data)
            return
        }
        guard SettingsStore.shared.fetchSpotifyArtwork,
              let urlString = track.artworkURL,
              let url = URL(string: urlString),
              !fetchingArtwork else { return }
        fetchingArtwork = true
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.fetchingArtwork = false } }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            try? data.write(to: cached)
            await MainActor.run { self.setArtwork(data: data) }
        }
    }

    private func setArtwork(data: Data?) {
        guard let data, let image = NSImage(data: data) else { return }
        artwork = image.scaled(maxSide: 256)
    }

    // MARK: Transport

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    private func command(_ verb: String) {
        guard let player = Player.allCases.first(where: { $0.isRunning }) else { return }
        let app = player.rawValue
        queue.async {
            _ = Self.run("tell application \"\(app)\" to \(verb)")
            Task { @MainActor in self.pollAfterCommand() }
        }
    }

    private func pollAfterCommand() {
        // Short delay so the player has actually changed state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.poll()
        }
    }

    // MARK: AppleScript plumbing

    nonisolated private static func run(_ source: String) -> Result<[String], Error> {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(NSError(domain: "Notch", code: -1))
        }
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            return .failure(NSError(domain: "Notch", code: code))
        }
        let text = descriptor.stringValue ?? ""
        return .success(text.components(separatedBy: "\u{1F}"))
    }

    nonisolated private static func runArtworkData() -> Data? {
        let source = """
        tell application "Music"
            try
                set d to data of artwork 1 of current track
                return d
            end try
            return ""
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let descriptor = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return descriptor.data
    }

    /// One script per player. `is running` is checked first so the player is
    /// never launched, and each field is guarded individually.
    nonisolated private static let spotifyScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            set out to ""
            try
                set out to out & (player state as string) & "\u{1F}"
                set out to out & (name of current track) & "\u{1F}"
                set out to out & (artist of current track) & "\u{1F}"
                set out to out & (album of current track) & "\u{1F}"
                set out to out & ((duration of current track) as string) & "\u{1F}"
                set out to out & ((player position) as string) & "\u{1F}"
                set out to out & (artwork url of current track)
            end try
            return out
        end tell
    end if
    return ""
    """

    nonisolated private static let musicScript = """
    if application "Music" is running then
        tell application "Music"
            set out to ""
            try
                set out to out & (player state as string) & "\u{1F}"
                set out to out & (name of current track) & "\u{1F}"
                set out to out & (artist of current track) & "\u{1F}"
                set out to out & (album of current track) & "\u{1F}"
                set out to out & ((duration of current track) as string) & "\u{1F}"
                set out to out & ((player position) as string) & "\u{1F}"
            end try
            return out
        end tell
    end if
    return ""
    """
}

// MARK: - Lyrics (LRCLIB, free, no key, cached locally)

@MainActor
final class LyricsService: ObservableObject {
    struct Line: Equatable {
        var time: TimeInterval
        var text: String
    }

    enum Status: Equatable {
        case idle
        case loading
        case synced
        case plain
        case notFound
        case offline
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var plain: String?
    @Published private(set) var status: Status = .idle

    private var key: String?

    func load(title: String, artist: String, album: String, duration: TimeInterval) {
        let newKey = cacheKey(title.lowercased(), artist.lowercased(), String(Int(duration)))
        guard newKey != key else { return }
        key = newKey
        lines = []
        plain = nil

        let file = AppPaths.lyrics.appendingPathComponent(newKey + ".json")
        if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(Cache.self, from: data) {
            apply(cached)
            return
        }

        status = .loading
        Task { [weak self] in
            let result = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
            guard let self else { return }
            switch result {
            case .success(let cache):
                if let data = try? JSONEncoder().encode(cache) { try? data.write(to: file) }
                self.apply(cache)
            case .failure:
                self.status = .notFound
            }
        }
    }

    /// Current line for a playback position, binary search over the LRC timings.
    func line(at position: TimeInterval) -> String? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard let index = found, index < lines.count else { return nil }
        let text = lines[index].text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private func apply(_ cache: Cache) {
        if let synced = cache.synced, !synced.isEmpty {
            lines = Self.parse(synced)
            status = lines.isEmpty ? .notFound : .synced
            plain = cache.plain
        } else if let plain = cache.plain, !plain.isEmpty {
            self.plain = plain
            lines = []
            status = .plain
        } else {
            status = .notFound
        }
    }

    private struct Cache: Codable {
        var synced: String?
        var plain: String?
    }

    private enum FetchResult {
        case success(Cache)
        case failure(Error)
    }

    private static func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> FetchResult {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]
        if let cache = await request(components.url) { return .success(cache) }

        // Fall back to search, then take the first hit that has synced lyrics.
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = search.url,
              let (data, _) = try? await session.data(from: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .failure(URLError(.badServerResponse))
        }
        for item in list {
            let synced = item["syncedLyrics"] as? String
            let plain = item["plainLyrics"] as? String
            if (synced?.isEmpty == false) || (plain?.isEmpty == false) {
                return .success(Cache(synced: synced, plain: plain))
            }
        }
        return .failure(URLError(.resourceUnavailable))
    }

    private static func request(_ url: URL?) async -> Cache? {
        guard let url, let (data, response) = try? await session.data(from: url) else { return nil }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let synced = item["syncedLyrics"] as? String
        let plain = item["plainLyrics"] as? String
        guard (synced?.isEmpty == false) || (plain?.isEmpty == false) else { return nil }
        return Cache(synced: synced, plain: plain)
    }

    private static var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = ["User-Agent": "Notch/1.0 (macOS; local lyrics lookup)"]
        return URLSession(configuration: config)
    }()

    /// Minimal LRC parser: "[mm:ss.xx] text", several stamps per line allowed.
    static func parse(_ lrc: String) -> [Line] {
        var out: [Line] = []
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = raw
            var times: [TimeInterval] = []
            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]") else { break }
                let stamp = String(rest[rest.index(after: rest.startIndex)..<close])
                rest = String(rest[rest.index(after: close)...])
                guard let time = parseStamp(stamp) else { continue }
                times.append(time)
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { out.append(Line(time: time, text: text)) }
        }
        return out.sorted { $0.time < $1.time }
    }

    private static func parseStamp(_ stamp: String) -> TimeInterval? {
        let parts = stamp.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]) else { return nil }
        return minutes * 60 + (Double(parts[1]) ?? 0)
    }
}
