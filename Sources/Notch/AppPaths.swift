import AppKit
import SwiftUI

/// Where the island's local files live: lyrics cache, artwork cache, socket, logs.
enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var lyrics: URL { sub("Lyrics") }
    static var artwork: URL { sub("Artwork") }
    static var socket: URL { support.appendingPathComponent("notch.sock") }
    static var claudeState: URL { support.appendingPathComponent("claude.json") }

    private static func sub(_ name: String) -> URL {
        let dir = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// A cache key that is stable across launches.
func cacheKey(_ parts: String...) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in parts.joined(separator: "\u{1}").utf8 {
        hash = (hash ^ UInt64(byte)) &* 0x100000001b3
    }
    return String(hash, radix: 16)
}

extension NSImage {
    /// Downscale + flatten, for artwork that only ever gets drawn small.
    func scaled(maxSide: CGFloat) -> NSImage {
        let size = self.size
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let image = NSImage(size: newSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize))
        image.unlockFocus()
        return image
    }
}

extension Date {
    /// "now", "4m", "2h", "18:02" — the shape used in the messages tile.
    func shortStamp(now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(self)
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if Calendar.current.isDateInToday(self) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: self)
        }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: self)
    }
}

extension TimeInterval {
    var mmss: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Runs a shell command line and returns stdout (used for networksetup and defaults).
@discardableResult
func shell(_ launchPath: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}
