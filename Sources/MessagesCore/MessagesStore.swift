import Foundation
import SQLite3

public enum MessagesStoreError: Error, LocalizedError {
    case cannotOpen
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "Can't open Messages. Grant Full Disk Access to this app in " +
                "System Settings → Privacy & Security → Full Disk Access, then relaunch."
        case .queryFailed(let msg):
            return "Query failed: \(msg)"
        }
    }
}

public final class MessagesStore {
    public init() {}

    public func loadAllMessages() throws -> [Message] {
        let dbPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Messages/chat.db")
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw MessagesStoreError.cannotOpen
        }
        defer { sqlite3_close(db) }
        // Messages.app can be writing to chat.db at the same time we're reading
        // it (receiving a text mid-load). Without this, a lock contention would
        // make sqlite3_step return SQLITE_BUSY instead of SQLITE_ROW, and the old
        // `while ... == SQLITE_ROW` loop below would silently treat that as "no
        // more rows" — truncating the load with zero indication anything went
        // wrong. Let SQLite itself retry for up to 5s before we give up.
        sqlite3_busy_timeout(db, 5000)

        let sql = """
            SELECT message.ROWID as id, message.date as date, message.is_from_me as from_me,
                   message.text as text, message.attributedBody as body,
                   COALESCE(NULLIF(chat.display_name, ''), chat.chat_identifier) as chat_name,
                   handle.id as handle_id
            FROM message
            JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
            JOIN chat ON chat.ROWID = chat_message_join.chat_id
            LEFT JOIN handle ON handle.ROWID = message.handle_id
            WHERE message.associated_message_type = 0
            ORDER BY message.date ASC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MessagesStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [Message] = []
        stepLoop: while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW:
                let id = Int(sqlite3_column_int64(stmt, 0))
                let rawDate = sqlite3_column_int64(stmt, 1)
                let isFromMe = sqlite3_column_int(stmt, 2) != 0
                let plainText = columnText(stmt, 3)
                guard let text = plainText ?? decodeAttributedBody(columnBlob(stmt, 4)),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                results.append(Message(
                    id: id,
                    date: Self.appleDateToDate(rawDate),
                    isFromMe: isFromMe,
                    text: text,
                    chatName: columnText(stmt, 5) ?? "Unknown",
                    handleID: columnText(stmt, 6)
                ))
            case SQLITE_DONE:
                break stepLoop
            default:
                // SQLITE_BUSY/SQLITE_LOCKED after the retry window, or a real
                // error — surface it instead of silently returning a partial list.
                throw MessagesStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        return results
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> [UInt8]? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let length = Int(sqlite3_column_bytes(stmt, index))
        return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: length))
    }

    // Apple epoch is 2001-01-01; macOS Big Sur+ stores `date` in nanoseconds,
    // older Messages databases store it in seconds.
    private static let appleEpochOffsetSeconds: TimeInterval = 978_307_200

    static func appleDateToDate(_ raw: Int64) -> Date {
        let seconds = raw > 1_000_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
        return Date(timeIntervalSince1970: appleEpochOffsetSeconds + seconds)
    }
}

// Ported from the validated chat.db importer in legal-evidence-eagle (app.html,
// decodeAttributedBody) — exact-match verified 62/62 against plain-text ground truth.
//
// iMessage stores most message bodies as a legacy NSArchiver ("typedstream") blob,
// not plain text (macOS Big Sur+). Full typedstream parsing is a lot of code for one
// string; this walks the NSString marker's length-prefixed payloads and picks the
// longest one that isn't an Apple internal key name (NSDictionary,
// __kIMFileTransferGUIDAttributeName, etc. — structural metadata in the same blob,
// not message content). Known ceiling: a real message that starts with "NS" or
// "__k" would be wrongly filtered.
let nsStringMarker: [UInt8] = Array("NSString".utf8)

func isAppleInternalKey(_ text: String) -> Bool {
    text.hasPrefix("__k") || text.hasPrefix("NS") || text == "streamtyped"
}

func decodeAttributedBody(_ bytes: [UInt8]?) -> String? {
    guard let bytes, !bytes.isEmpty else { return nil }
    guard let markerStart = firstIndex(of: nsStringMarker, in: bytes) else { return nil }

    var i = markerStart + nsStringMarker.count
    let scanLimit = min(bytes.count - 1, i + 60)
    var best: (length: Int, text: String)?

    while i < scanLimit {
        let length: Int
        let start: Int
        if bytes[i] == 0x81 {
            length = Int(bytes[i + 1]) | (Int(bytes[i + 2]) << 8)
            start = i + 3
        } else {
            length = Int(bytes[i])
            start = i + 1
        }
        if length > 0, start + length <= bytes.count {
            let candidate = Data(bytes[start..<(start + length)])
            if let text = String(data: candidate, encoding: .utf8),
               isPrintable(text),
               !isAppleInternalKey(text) {
                if best == nil || length >= best!.length {
                    best = (length, text)
                }
            }
        }
        i += 1
    }
    return best?.text
}

private let printableASCII = CharacterSet(charactersIn: UnicodeScalar(0x20)...UnicodeScalar(0x7E))

func isPrintable(_ text: String) -> Bool {
    text.contains("\n") || text.rangeOfCharacter(from: printableASCII) != nil
}

func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
    guard haystack.count >= needle.count else { return nil }
    for i in 0...(haystack.count - needle.count) {
        if Array(haystack[i..<(i + needle.count)]) == needle {
            return i
        }
    }
    return nil
}
