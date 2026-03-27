import Foundation
import Combine

/// Manages the sing-box process: start, stop, traffic stats polling.
@MainActor
final class SingBoxManager: ObservableObject {

    static let shared = SingBoxManager()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var trafficStats = TrafficStats()
    @Published var elapsedTime: TimeInterval = 0

    private var singboxPID: Int32?
    private var statsTimer: Timer?
    private var elapsedTimer: Timer?
    private var connectTime: Date?

    private let clashAPIBase = "http://127.0.0.1:9090"

    // MARK: - Locate sing-box binary

    private func findSingBox() -> String? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("sing-box").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let paths = [
            "/usr/local/bin/sing-box",
            "/opt/homebrew/bin/sing-box",
            "/usr/bin/sing-box"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Connect / Disconnect

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

        // Single osascript call: kill old + start new — ONE password prompt
        let script = "do shell script \"pkill -f sing-box; sleep 0.3; \(singboxPath) run -c '\(configFile)' > /tmp/singbox.log 2>&1 & echo $!\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            connectionState = .error(error.localizedDescription)
            return
        }

        if proc.terminationStatus != 0 {
            connectionState = .disconnected
            return
        }

        let pidData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let pidString = String(data: pidData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        singboxPID = Int32(pidString)

        // Wait for sing-box to initialize, then check if process is alive
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let isRunning = checkPIDAlive(pidString)

        if isRunning {
            connectionState = .connected
            connectTime = Date()
            startTimers()
            if let pid = singboxPID { monitorPID(pid) }
        } else {
            let log = (try? String(contentsOfFile: "/tmp/singbox.log", encoding: .utf8)) ?? ""
            let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
            let fatalLine = lines.first(where: { $0.contains("FATAL") || $0.contains("fatal") })
            let errMsg = fatalLine ?? lines.last ?? "sing-box не запустился"
            connectionState = .error(stripAnsi(errMsg))
        }
    }

    // Check if process is alive using `kill -0` via shell (avoids sandbox URLSession issue)
    private func checkPIDAlive(_ pidString: String) -> Bool {
        guard !pidString.isEmpty, let pid = Int32(pidString) else { return false }
        return kill(pid, 0) == 0
    }

    private func monitorPID(_ pid: Int32) {
        Task.detached { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let alive = kill(pid, 0) == 0
                if !alive {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        if self.connectionState == .connected {
                            let log = (try? String(contentsOfFile: "/tmp/singbox.log", encoding: .utf8)) ?? ""
                            let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
                            let fatalLine = lines.first(where: { $0.contains("FATAL") || $0.contains("fatal") })
                            let msg = self.stripAnsi(fatalLine ?? "sing-box завершился неожиданно")
                            self.connectionState = .error(msg)
                            self.stopTimers()
                        }
                    }
                    break
                }
            }
        }
    }

    private func stripAnsi(_ str: String) -> String {
        str.replacingOccurrences(of: "\\[\\d+m", with: "", options: .regularExpression)
           .replacingOccurrences(of: "[33m", with: "")
           .replacingOccurrences(of: "[31m", with: "")
           .replacingOccurrences(of: "[0m", with: "")
           .replacingOccurrences(of: "[0000]", with: "")
           .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func disconnect() {
        guard connectionState == .connected || connectionState == .connecting else { return }
        connectionState = .disconnecting
        stopTimers()

        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        killProc.arguments = ["-e", "do shell script \"pkill -f sing-box\" with administrator privileges"]
        try? killProc.run()
        killProc.waitUntilExit()

        singboxPID = nil
        connectionState = .disconnected
        trafficStats = TrafficStats()
        elapsedTime = 0
        connectTime = nil
    }

    // MARK: - Timers

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

    // MARK: - Traffic Stats (via curl to avoid sandbox URLSession restrictions)

    private func pollTrafficStats() async {
        let result = await runShell("curl -s http://127.0.0.1:9090/connections")
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

    private func runShell(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", command]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(Int(value)) \(units[unitIndex])" }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    var formattedElapsed: String {
        let total = Int(elapsedTime)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
