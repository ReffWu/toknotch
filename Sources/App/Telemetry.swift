import Foundation

@MainActor
enum Telemetry {
    static let key = "sharesUsageStatistics"
    private static let endpoint = URL(string: "https://softfold-telemetry.reffwu.workers.dev/heartbeat")!
    private static var sending = false

    static func start() {
        UserDefaults.standard.register(defaults: [key: true])
        send()
        Task {
            while true {
                try? await Task.sleep(for: .seconds(3600))
                send()
            }
        }
    }

    static func recordActivity() {
        UserDefaults.standard.set(today, forKey: "lastActivityDay")
        send()
    }

    private static var today: String {
        Date().ISO8601Format(.iso8601Date(timeZone: TimeZone(identifier: "UTC")!))
    }

    private static func send() {
        let defaults = UserDefaults.standard
        let day = today
        let didActivity = defaults.string(forKey: "lastActivityDay") == day
        guard defaults.bool(forKey: key), !sending,
            defaults.string(forKey: "heartbeatDay") != day
                || (didActivity && defaults.string(forKey: "heartbeatActivityDay") != day)
        else { return }

        let install = defaults.string(forKey: "installID") ?? UUID().uuidString
        defaults.set(install, forKey: "installID")
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let body: [String: Any] = [
            "app_id": "toknotch",
            "install_id": install,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "os_version": "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            "model": model,
            "folded": didActivity,
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        sending = true
        Task {
            defer { sending = false }
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                (response as? HTTPURLResponse)?.statusCode == 204
            else { return }
            defaults.set(day, forKey: "heartbeatDay")
            if didActivity { defaults.set(day, forKey: "heartbeatActivityDay") }
        }
    }

    private static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &value, &size, nil, 0)
        return String(cString: value)
    }
}
