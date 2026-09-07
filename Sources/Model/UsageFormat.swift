import Foundation

/// How token counts, money and proportions are written.
///
/// Everything here goes through Foundation with an explicit `Locale`, rather
/// than through units written out by hand. That is not laziness — it is the
/// only way to be right. Each language groups large numbers its own way, and
/// the differences are not cosmetic:
///
///     15,434,419,444   en  15.4B      zh-Hans  154.3亿
///                      ja  154.3億    ko       154.3억
///                      de  15,4 Mrd.  fr       15,4 Md
///                      es  15,4 mil M ru       15,4 млрд
///
/// English counts in thousands, Chinese and Japanese and Korean in myriads
/// (10⁴), and the separators move too — German writes 15,4 where English
/// writes 15.4. Showing "15.4B" to somebody who counts in 亿 makes them do
/// arithmetic on every glance, which is the one thing a readout on a screen
/// edge must never ask for.
enum UsageFormat {
    /// `154.3亿` / `15.4B` / `15,4 Mrd.` — a token count, abbreviated the way
    /// this language abbreviates.
    static func tokens(_ count: Int64, _ language: AppLanguage) -> String {
        count.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
                .locale(language.locale)
        )
    }

    /// `$43.43` / `4.929,28 $` — the exact figure, with the currency where this
    /// language puts it.
    static func money(_ amount: Double, _ language: AppLanguage) -> String {
        amount.formatted(.currency(code: "USD").locale(language.locale))
    }

    /// The shorter form, for places where the cents would only be noise.
    ///
    /// Whole units rather than an abbreviation. Compact *currency* needs macOS
    /// 15, and composing one by hand would put the symbol on the wrong side in
    /// half the languages here — $744 is shorter than the cents-bearing form
    /// and clearer than $0.7k either way.
    static func moneyShort(_ amount: Double, _ language: AppLanguage) -> String {
        amount.formatted(
            .currency(code: "USD").precision(.fractionLength(0)).locale(language.locale)
        )
    }

    /// `78,264` / `78.264` — a plain count, grouped this language's way.
    static func count(_ value: Int, _ language: AppLanguage) -> String {
        value.formatted(.number.locale(language.locale))
    }

    static func percent(_ fraction: Double, _ language: AppLanguage) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(language.locale))
    }

    /// A share that keeps one decimal while it is small, because a model with a
    /// real 0.4% share reading as 0% looks like a bug rather than a small
    /// number.
    static func share(_ fraction: Double, _ language: AppLanguage) -> String {
        let digits = (fraction > 0 && fraction < 0.1) ? 1 : 0
        return fraction.formatted(
            .percent.precision(.fractionLength(digits)).locale(language.locale)
        )
    }

    /// A multiple of a subscription's cost — `18.7×`.
    ///
    /// The multiplication sign is U+00D7, not the letter x: at 32pt the letter
    /// is unmistakably a letter, and this is a unit.
    static func multiple(_ value: Double, _ language: AppLanguage) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(language.locale)) + "×"
    }

    /// A model id cleaned up, but never shortened past recognition.
    ///
    /// The vendor prefix stays. A primary card's model table mixes vendors —
    /// Claude, GPT and DeepSeek in the same three rows — so stripping it is
    /// exactly backwards: `claude-opus-5` and `gpt-5.6-terra` become `opus-5`
    /// and `5.6-terra`, and the reader loses the one part of the name that says
    /// whose model it was. Only the parts that carry no information go: the
    /// route prefix a local model is filed under, and the `(local)` note that
    /// repeats what the rest of the name already says.
    static func modelName(_ id: String) -> String {
        var name = id
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        if let note = name.range(of: " (local)", options: .caseInsensitive) {
            name = String(name[..<note.lowerBound])
        }
        return name.isEmpty ? id : name
    }

    /// A date written the way this language writes a day of the year —
    /// `Sep 7` / `9月7日` / `7. Sept.` / `7 сент.`
    static func day(_ date: Date, _ language: AppLanguage,
                    calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    /// A date and time, for "last updated at".
    static func moment(_ date: Date, _ language: AppLanguage) -> String {
        date.formatted(.dateTime.hour().minute().second().locale(language.locale))
    }
}
