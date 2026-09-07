import os

/// An agent app has no window to print into, so anything worth diagnosing has
/// to go somewhere you can read it:
///
///     log stream --predicate 'subsystem == "com.reff.toknotch"' --level debug
enum Log {
    static let usage = Logger(subsystem: "com.reff.toknotch", category: "usage")
    static let sessions = Logger(subsystem: "com.reff.toknotch", category: "sessions")
}
