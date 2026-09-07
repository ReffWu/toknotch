import Foundation

extension AppLanguage {
    /// One line of user-facing text, in this language.
    ///
    /// Reads from the language's own `.lproj` rather than through
    /// `NSLocalizedString`, because the language here is a setting rather than
    /// a property of the Mac: somebody whose system is in English may still
    /// want to read this in 日本語, and the standard lookup would give them
    /// English no matter what they chose.
    ///
    /// A missing key returns the key itself. That is deliberately ugly — a
    /// string that shows up as `ring.today.title` on screen gets fixed, where
    /// one that silently falls back to English does not.
    func t(_ key: String) -> String {
        Self.bundle(for: resolved).localizedString(forKey: key, value: key, table: nil)
    }

    /// The same, with values substituted — `%@` for text, `%d` for a count.
    ///
    /// Order matters between languages, so every format string here uses
    /// positional specifiers (`%1$@`) where it takes more than one value: what
    /// English says as "40% of your best day" another language may have to say
    /// the other way round, and a translator has to be able to move them.
    func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: arguments)
    }

    /// Bundles are looked up once. `Bundle(path:)` hits the filesystem, and
    /// this is called for every string on every card.
    private static var bundles: [String: Bundle] = [:]
    private static let lock = NSLock()

    private static func bundle(for language: AppLanguage) -> Bundle {
        lock.lock()
        defer { lock.unlock() }
        if let cached = bundles[language.rawValue] { return cached }
        let bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        bundles[language.rawValue] = bundle
        return bundle
    }

    /// Every language this build actually ships strings for.
    ///
    /// A language whose `.lproj` never made it into the bundle would show its
    /// keys on screen, so it is not offered.
    static var available: [AppLanguage] {
        allCases.filter { language in
            language == .system
                || Bundle.main.path(forResource: language.rawValue, ofType: "lproj") != nil
        }
    }
}
