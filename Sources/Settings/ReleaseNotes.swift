import Foundation

/// What one release changed, in the app's own words.
struct ReleaseNote: Equatable {
    /// Matched against `CFBundleShortVersionString`, so it has to be exactly
    /// the string `MARKETING_VERSION` is set to.
    let version: String
    /// One line under the title. What this release is *about*.
    let headline: String
    let changes: [Change]

    /// A title carries the change; the detail is optional, so a small fix can
    /// be a single line rather than a line padded out to match its neighbours.
    struct Change: Equatable {
        let title: String
        let detail: String

        init(title: String, detail: String = "") {
            self.title = title
            self.detail = detail
        }
    }
}

/// The release history the app ships with.
enum ReleaseNotes {
    /// Every release, read in the given language.
    ///
    /// The text lives in the strings table rather than here. This is the one
    /// dialogue a person is shown on the launch after an update, and greeting
    /// a reader who chose 한국어 with a screen of another language is worse
    /// than greeting them with nothing.
    static func all(in language: AppLanguage) -> [ReleaseNote] {
        [
            ReleaseNote(
                version: "1.2.1",
                headline: language.t("whatsNew.v121.headline"),
                changes: [
                    ReleaseNote.Change(title: language.t("whatsNew.v121.colours.title"),
                                       detail: language.t("whatsNew.v121.colours.detail")),
                    ReleaseNote.Change(title: language.t("whatsNew.v121.about.title"),
                                       detail: language.t("whatsNew.v121.about.detail")),
                    ReleaseNote.Change(title: language.t("whatsNew.v121.fold.title"))
                ]
            ),
            ReleaseNote(
                version: "1.2.0",
                headline: language.t("whatsNew.v120.headline"),
                changes: ["payback", "menuBar", "simpler"].map { entry in
                    ReleaseNote.Change(
                        title: language.t("whatsNew.v120.\(entry).title"),
                        detail: language.t("whatsNew.v120.\(entry).detail")
                    )
                }
            ),
            ReleaseNote(
                version: "1.1.0",
                headline: language.t("whatsNew.v110.headline"),
                changes: ["updates", "languages", "icon", "simpler"].map { entry in
                    ReleaseNote.Change(
                        title: language.t("whatsNew.v110.\(entry).title"),
                        detail: language.t("whatsNew.v110.\(entry).detail")
                    )
                }
            ),
            ReleaseNote(
                version: "1.0.0",
                headline: language.t("whatsNew.v100.headline"),
                // Ordered by what somebody opening this wants to know first:
                // what the subscriptions gave back, then what is on screen,
                // then how to read it.
                changes: ["payback", "rings", "baseline", "vendors", "makers", "local"]
                    .map { entry in
                        ReleaseNote.Change(
                            title: language.t("whatsNew.v100.\(entry).title"),
                            detail: language.t("whatsNew.v100.\(entry).detail")
                        )
                    }
            )
        ]
    }

    static func note(for version: String, in language: AppLanguage) -> ReleaseNote? {
        all(in: language).first { $0.version == version }
    }

    /// The note worth showing on this launch, if there is one.
    static func unseen(in version: String,
                       lastSeen: String?,
                       notes: [ReleaseNote]) -> ReleaseNote? {
        guard lastSeen != version else { return nil }
        return notes.first { $0.version == version }
    }
}
