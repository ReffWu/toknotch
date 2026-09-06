import Foundation
import SQLite3

/// Read-only access to another app's SQLite store.
///
/// Both Cursor and Codex keep their state this way, and both run it in WAL mode,
/// which makes opening it more delicate than it looks:
///
/// - `immutable=1` tells SQLite to ignore the write-ahead log entirely, so a
///   running app's most recent writes are invisible. That is how a live agent
///   looks idle and a rotated token looks current.
/// - `mode=ro` sees the log, but needs the `-shm` sidecar to do it — and that
///   file exists only *while the owning app is running*. Once it has quit and
///   checkpointed, a read-only open fails outright with "unable to open
///   database file".
///
/// So: `mode=ro` first, `immutable=1` second. The fallback is only ever reached
/// when there is no write-ahead log left to miss, which is exactly when ignoring
/// it costs nothing.
enum SQLiteStore {
    static func open(_ url: URL) -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        for query in ["mode=ro", "immutable=1"] {
            var db: OpaquePointer?
            if sqlite3_open_v2("file:\(url.path)?\(query)", &db,
                               SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
               let db {
                return db
            }
            sqlite3_close(db)
        }
        return nil
    }

    /// Every column of every row, as text. Needed where one row carries more
    /// than one fact — a thread's title *and* when it was last touched — and
    /// two queries would be two chances for them to disagree.
    static func rows(in db: OpaquePointer?, sql: String, columns: Int) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var out: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String] = []
            for index in 0..<Int32(columns) {
                row.append(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "")
            }
            out.append(row)
        }
        return out
    }

    /// First column of every row, as text.
    static func rows(in db: OpaquePointer?, sql: String, bind: String? = nil) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        if let bind {
            sqlite3_bind_text(statement, 1, bind, -1,
                              unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        var out: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 0) { out.append(String(cString: raw)) }
        }
        return out
    }
}
