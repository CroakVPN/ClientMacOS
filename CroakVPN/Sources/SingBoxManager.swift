import Foundation
import Combine

@MainActor
final class SingBoxManager: ObservableObject {

    static let shared = SingBoxManager()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var trafficStats = TrafficStats()
    @Published var elapsedTime: TimeInterval = 0

    private var statsTimer: Timer?
    private var elapsedTimer: Timer?
    private var connectTime: Date?

    private let clashAPIBase = "127.0.0.1:9090"

    private func findSingBox() -> String? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("sing-box").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let paths = ["/usr/local/bin/sing-box", "/opt/homebrew/bin/sing-box", "/usr/bin/sing-box"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func shell(_ cmd: String) async -> (String, Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", cmd]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                try? p.run()
                p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                cont.resume(returning: (out, p.terminationStatus))
            }
        }
    }

    private func checkAPI() async -> Bool {
        for _ in 0..<12 {
            let (out, _) = await shell("curl -s --connect-timeout 1 --max-time 1 http://\(clashAPIBase)/version")
            if out.contains("sing-box") { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    func connect() async {
        guard connectionState == .disconnected || {
            if case .error = connectionState { return true }
            return false
        }() else { return }

        connectionState = .connecting

        guard let singboxPath = findSingBox() else {
            connectionState = .error("sing-box не найден")
            return
        }

        guard PrefsManager.shared.getSingboxConfig() != nil else {
            connectionState = .error("Нет конфигурации. Добавьте подписку.")
            return
        }

        let configFile = PrefsManager.shared.singboxConfigPath.path
        let logFile = NSHomeDirectory() + "/singbox_croak.log"
        let scriptPath = NSTemporaryDirectory() + "croak_launch.applescript"

        let appleScript = "do shell script \"pkill -f sing-box; sleep 0.3; \(singboxPath) run -c \(configFile) > \(logFile) 2>&1 &\" with administrator privileges"
        try? appleScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        let (_, status) = await shell("/usr/bin/osascript '\(scriptPath)'")

        if status != 0 {
            connectionState = .disconnected
            return
        }

        let isRunning = await checkAPI()

        if isRunning {
            connectionState = .connected
            connectTime = Date()
            startTimers()
        } else {
            let log = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
            let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
            let fatal = lines.first { $0.contains("FATAL") || $0.contains("fatal") }
            connectionState = .error(stripAnsi(fatal ?? lines.last ?? "sing-box не запустился"))
        }
    }

    func disconnect() {
        guard connectionState == .connected || connectionState == .connecting else { return }
        connectionState = .disconnecting
        stopTimers()

        let scriptPath = NSTemporaryDirectory() + "croak_kill.applescript"
        let appleScript = "do shell script \"pkill -f sing-box\" with administrator privileges"
        try? appleScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        Task {
            await shell("/usr/bin/osascript '\(scriptPath)'")
            await MainActor.run {
                self.connectionState = .disconnected
                self.trafficStats = TrafficStats()
                self.elapsedTime = 0
                self.connectTime = nil
            }
        }
    }

    private func startTimers() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.pollTrafficStats() }
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.connectTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimers() {
        statsTimer?.invalidate(); statsTimer = nil
        elapsedTimer?.invalidate(); elapsedTimer = nil
    }

    private func pollTrafficStats() async {
        let (result, _) = await shell("curl -s --max-time 1 http://\(clashAPIBase)/connections")
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let dlTotal = json["downloadTotal"] as? Int64 ?? 0
        let ulTotal = json["uploadTotal"] as? Int64 ?? 0
        let dlSpeed = dlTotal - trafficStats.totalDownload
        let ulSpeed = ulTotal - trafficStats.totalUpload
        trafficStats = TrafficStats(
            downloadSpeed: formatSpeed(dlSpeed > 0 ? dlSpeed : 0),
            uploadSpeed: formatSpeed(ulSpeed > 0 ? ulSpeed : 0),
            totalDownload: dlTotal,
            totalUpload: ulTotal
        )
    }

    private func stripAnsi(_ str: String) -> String {
        str.replacingOccurrences(of: "\\[\\d+m", with: "", options: .regularExpression)
           .replacingOccurrences(of: "[33m", with: "").replacingOccurrences(of: "[31m", with: "")
           .replacingOccurrences(of: "[0m", with: "").replacingOccurrences(of: "[0000]", with: "")
           .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 { value /= 1024; unitIndex += 1 }
        if unitIndex == 0 { return "\(Int(value)) \(units[unitIndex])" }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    var formattedElapsed: String {
        let total = Int(elapsedTime)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
