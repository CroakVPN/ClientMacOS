import Foundation

/// Manages subscription URL and sing-box config persistence.
final class PrefsManager {

    static let shared = PrefsManager()

    private let configDir: URL
    private let prefsPath: URL
    let singboxConfigPath: URL

    private(set) var subscriptionUrl: String?

    var hasSubscription: Bool { subscriptionUrl?.isEmpty == false }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        configDir = appSupport.appendingPathComponent("CroakVPN", isDirectory: true)

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        prefsPath = configDir.appendingPathComponent("prefs.txt")
        singboxConfigPath = configDir.appendingPathComponent("config.json")
        load()
    }

    var configDirectory: String { configDir.path }

    // MARK: - Public

    func saveSubscription(url: String, singboxConfig: String) {
        subscriptionUrl = url
        try? singboxConfig.write(to: singboxConfigPath, atomically: true, encoding: .utf8)
        try? url.write(to: prefsPath, atomically: true, encoding: .utf8)
    }

    func getSingboxConfig() -> String? {
        guard FileManager.default.fileExists(atPath: singboxConfigPath.path) else { return nil }
        return try? String(contentsOf: singboxConfigPath, encoding: .utf8)
    }

    func clearSubscription() {
        subscriptionUrl = nil
        try? FileManager.default.removeItem(at: singboxConfigPath)
        try? FileManager.default.removeItem(at: prefsPath)
    }

    // MARK: - Private

    private func load() {
        guard FileManager.default.fileExists(atPath: prefsPath.path) else { return }
        subscriptionUrl = (try? String(contentsOf: prefsPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
