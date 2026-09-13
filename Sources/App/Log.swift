import os

/// An agent app has no window to print into, so anything worth diagnosing has
/// to go somewhere you can read it:
///
///     log stream --predicate 'subsystem == "com.reffwu.toknotch"' --level debug
enum Log {
    static let usage = Logger(subsystem: "com.reffwu.toknotch", category: "usage")
    static let sessions = Logger(subsystem: "com.reffwu.toknotch", category: "sessions")
}
