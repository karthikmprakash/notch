import AppKit
import SQLite3
import SwiftUI

/// Reads ~/Library/Messages/chat.db read-only. macOS will not prompt for this:
/// the database is only reachable with Full Disk Access, so the tile says so.
@MainActor
final class MessagesService: ObservableObject {
    struct Row: Identifiable, Equatable {
        var id: String
        var name: String
        var unread: Int
        var preview: String
        var date: Date
    }

    enum Status: Equatable {
        case idle
        case ok
        case needsFullDiskAccess
        case error(String)
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var status: Status = .idle

    private var timer: Timer?

    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Messages/chat.db")
        var handle: OpaquePointer?
        // Read-only: this app never writes to your messages database.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            status = .needsFullDiskAccess
            rows = []
            return
        }
        defer { sqlite3_close(db) }

        // Newer macOS stores the text in attributedBody; text is often NULL.
        let sql = """
        SELECT c.ROWID,
               COALESCE(c.display_name, '') ,
               c.chat_identifier,
               (SELECT COUNT(*) FROM message m2
                  JOIN chat_message_join j2 ON j2.message_id = m2.ROWID
                 WHERE j2.chat_id = c.ROWID AND m2.is_from_me = 0 AND m2.is_read = 0) AS unread,
               m.date, m.text, m.attributedBody, m.is_from_me
          FROM chat c
          JOIN chat_message_join j ON j.chat_id = c.ROWID
          JOIN message m ON m.ROWID = j.message_id
         WHERE m.ROWID IN (
               SELECT MAX(m3.ROWID) FROM message m3
                 JOIN chat_message_join j3 ON j3.message_id = m3.ROWID
                WHERE j3.chat_id = c.ROWID AND m3.is_from_me = 0)
           AND EXISTS (SELECT 1 FROM message m4
                 JOIN chat_message_join j4 ON j4.message_id = m4.ROWID
                WHERE j4.chat_id = c.ROWID AND m4.is_from_me = 0 AND m4.is_read = 0)
         ORDER BY m.date DESC
         LIMIT 2
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            status = .error(String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }

        var result: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let display = columnText(stmt, 1)
            let identifier = columnText(stmt, 2)
            let unread = Int(sqlite3_column_int64(stmt, 3))
            let raw = sqlite3_column_int64(stmt, 4)
            let text = columnText(stmt, 5)
            let body = columnBlob(stmt, 6)
            let preview = text.isEmpty ? Self.decodeAttributedBody(body) : text
            let name = Self.prettyName(display: display, identifier: identifier)
            result.append(Row(id: identifier,
                              name: name,
                              unread: max(unread, 1),
                              preview: preview.trimmingCharacters(in: .whitespacesAndNewlines),
                              date: Self.date(fromAppleStamp: raw)))
        }
        rows = result
        status = .ok
    }

    // MARK: Column helpers

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func columnBlob(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }

    /// chat.db dates are nanoseconds since 2001 on modern macOS, seconds before that.
    static func date(fromAppleStamp stamp: Int64) -> Date {
        if stamp > 1_000_000_000_000 {
            return Date(timeIntervalSinceReferenceDate: Double(stamp) / 1_000_000_000)
        }
        return Date(timeIntervalSinceReferenceDate: Double(stamp))
    }

    static func prettyName(display: String, identifier: String) -> String {
        if !display.isEmpty { return display }
        // A phone number or email: keep it short.
        if identifier.contains("@") { return String(identifier.split(separator: "@")[0]) }
        let digits = identifier.filter { $0.isNumber }
        if digits.count >= 10 { return "+" + digits.suffix(10) }
        return identifier.isEmpty ? "Unknown" : identifier
    }

    /// attributedBody is a typedstream blob; the message text is the printable
    /// run after the marker the archiver writes in front of the string.
    static func decodeAttributedBody(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        let marker: [UInt8] = [0x01, 0x94, 0x84, 0x01, 0x2b]
        var start = data.startIndex
        if let range = data.range(of: Data(marker)) {
            start = range.upperBound
        } else if let range = data.range(of: Data("NSString".utf8)) {
            start = range.upperBound
        }
        guard start < data.endIndex else { return "" }
        let slice = data[start...]
        var bytes: [UInt8] = []
        for byte in slice {
            if byte == 0x86 || byte == 0x00 { break }
            bytes.append(byte)
        }
        // Drop the leading length/type bytes and keep everything printable.
        var text = String(decoding: bytes, as: UTF8.self)
        text = text.replacingOccurrences(of: "\u{FFFD}", with: "")
        text = text.unicodeScalars
            .filter { scalar in
                !scalar.properties.isDefaultIgnorableCodePoint && (scalar.value >= 32 || scalar == "\n")
            }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
