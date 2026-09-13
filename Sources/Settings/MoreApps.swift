import AppKit
import SwiftUI

/// The other apps Reff Wu makes, for the card at the foot of Settings.
///
/// Read from one list published on the artifacts site, so an app released
/// later appears in every copy of every app already installed, without any of
/// them having to ship an update. The list is public and fetched as a plain
/// file: nothing about this Mac or its usage is sent anywhere.
@MainActor
final class MoreApps: ObservableObject {
    static let shared = MoreApps()

    struct Entry: Decodable, Identifiable, Equatable {
        let id: String
        let bundleID: String
        let name: String
        let icon: URL
        let page: URL
        let tagline: [String: String]

        func tagline(in language: AppLanguage) -> String {
            tagline[language.resolved.rawValue] ?? tagline["en"] ?? ""
        }
    }

    private struct Catalog: Decodable {
        let apps: [Entry]
    }

    static let catalogURL = URL(string: "https://reffwu.github.io/artifacts/apps/catalog.json")!
    /// A day: new apps are rare, and a list checked on every open would be a
    /// network request with nothing to show for it.
    private static let freshFor: TimeInterval = 24 * 60 * 60

    /// Every app on the list except this one.
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var icons: [String: NSImage] = [:]

    private var isLoading = false
    private let directory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.reffwu.toknotch")
            .appendingPathComponent("MoreApps")
        showCached()
    }

    private var catalogFile: URL { directory.appendingPathComponent("catalog.json") }
    private func iconFile(for entry: Entry) -> URL {
        directory.appendingPathComponent("\(entry.id).png")
    }

    /// Called when the card appears. Cheap when the cached list is still fresh.
    func refreshIfStale() {
        guard !isLoading, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        let modified = (try? catalogFile.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        if let modified, Date().timeIntervalSince(modified) < Self.freshFor { return }

        isLoading = true
        Task {
            defer { isLoading = false }
            guard let (data, response) = try? await URLSession.shared.data(from: Self.catalogURL),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
            else { return }

            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: catalogFile)
            for entry in catalog.apps where entry.bundleID != Bundle.main.bundleIdentifier {
                if let (icon, _) = try? await URLSession.shared.data(from: entry.icon),
                   NSImage(data: icon) != nil {
                    try? icon.write(to: iconFile(for: entry))
                }
            }
            showCached()
        }
    }

    private func showCached() {
        guard let data = try? Data(contentsOf: catalogFile),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
        else { return }
        let others = catalog.apps.filter { $0.bundleID != Bundle.main.bundleIdentifier }
        entries = others
        icons = Dictionary(uniqueKeysWithValues: others.compactMap { entry in
            NSImage(contentsOf: iconFile(for: entry)).map { (entry.id, $0) }
        })
    }

    static func installedURL(for entry: Entry) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID)
    }
}

/// "More from Reff Wu": one row per app, with Get or Open.
///
/// Shown only once there is something to show. A card with nothing in it, or
/// one waiting on the network, would be the first thing on the page to look
/// broken.
struct MoreAppsGroup: View {
    let language: AppLanguage
    @ObservedObject private var store = MoreApps.shared

    var body: some View {
        // Loaded by the page this sits on, not here: with nothing to show
        // there is no view to appear, so an `onAppear` here would never fire.
        Group {
            if !store.entries.isEmpty {
                SettingsGroup(title: language.t("moreApps.title")) {
                    ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { SettingsDivider(inset: SettingsMetrics.rowPaddingH + 40 + 11) }
                        row(entry)
                    }
                }
            }
        }
    }

    private func row(_ entry: MoreApps.Entry) -> some View {
        let installed = MoreApps.installedURL(for: entry)
        return HStack(spacing: 11) {
            // Clipped to the icon's frame, as in the icon picker: the artwork
            // carries a shadow margin that would otherwise sit in the row.
            Group {
                if let icon = store.icons[entry.id] {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Color.primary.opacity(0.08)
                }
            }
            .frame(width: 40 * 1024 / 980, height: 40 * 1024 / 980)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 40 * 262 / 980, style: .circular))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name).font(.system(size: 13))
                Text(entry.tagline(in: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Button(language.t(installed == nil ? "moreApps.get" : "moreApps.open")) {
                if let installed {
                    NSWorkspace.shared.openApplication(at: installed,
                                                       configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.open(entry.page)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
