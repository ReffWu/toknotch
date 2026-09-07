import Foundation

/// How token counts and money are written on the notch.
///
/// The notch is read at a glance and out of the corner of an eye, so every
/// figure here is rounded to something a person can hold in their head. Exact
/// digits belong in the card, and even there only where they earn their place.
enum UsageFormat {
    /// `1.5万` / `16.1亿`, or `15.4k` / `1.61B`, following the reader's setting.
    ///
    /// Chinese groups by 万 (10⁴) and 亿 (10⁸), not by thousands — writing
    /// `1.61B` for a Chinese reader forces a mental conversion every single
    /// glance, which is exactly what a glanceable readout must not do.
    static func tokens(_ count: Int64, _ language: AppLanguage) -> String {
        let magnitude = abs(count)
        let sign = count < 0 ? "-" : ""

        switch language {
        case .chinese:
            if magnitude >= 100_000_000 {
                return sign + trimmed(Double(magnitude) / 100_000_000, "亿")
            } else if magnitude >= 10_000 {
                return sign + trimmed(Double(magnitude) / 10_000, "万")
            }
            return "\(count)"
        case .english:
            if magnitude >= 1_000_000_000 {
                return sign + trimmed(Double(magnitude) / 1_000_000_000, "B")
            } else if magnitude >= 1_000_000 {
                return sign + trimmed(Double(magnitude) / 1_000_000, "M")
            } else if magnitude >= 1_000 {
                return sign + trimmed(Double(magnitude) / 1_000, "k")
            }
            return "\(count)"
        }
    }

    /// One decimal below 100, none above it: `9.4亿` keeps its precision while
    /// `154亿` does not carry a digit nobody reads.
    private static func trimmed(_ value: Double, _ unit: String) -> String {
        value >= 100
            ? String(format: "%.0f%@", value, unit)
            : String(format: "%.1f%@", value, unit)
    }

    /// `$43.43` — the headline figure for money, always to the cent.
    static func money(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    /// `$4.9k` for the shorter form, where the cents would only be noise.
    static func moneyShort(_ amount: Double) -> String {
        abs(amount) >= 1_000
            ? String(format: "$%.1fk", amount / 1_000)
            : String(format: "$%.0f", amount)
    }

    /// `2,869` — thread-safe because a formatter is built per call; these are
    /// made a handful of times per refresh, not per frame.
    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", (fraction * 100).rounded())
    }

    /// A percentage that keeps one decimal while it is small, because a
    /// 0.4%-share model reading `0%` looks like a bug.
    static func share(_ fraction: Double) -> String {
        let value = fraction * 100
        return value < 10 && value > 0
            ? String(format: "%.1f%%", value)
            : String(format: "%.0f%%", value)
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
}
