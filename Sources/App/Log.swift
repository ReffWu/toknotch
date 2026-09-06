import os

/// An agent app has no window to print into, so anything worth diagnosing has
/// to go somewhere you can read it:
///
///     log stream --predicate 'subsystem == "com.vinz.codenotch"' --level debug
enum Log {
    static let usage = Logger(subsystem: "com.vinz.codenotch", category: "usage")
    static let sessions = Logger(subsystem: "com.vinz.codenotch", category: "sessions")
}
