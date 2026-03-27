import Foundation
import Combine

/// Manages the sing-box process: start, stop, traffic stats polling.
@MainActor
final class SingBoxManager: ObservableObject {

    static let shared = SingBoxManager()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var trafficStats = TrafficStats()
    @Published var elapsedTime: TimeInterval = 0

    private var process: Process?
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

        // Kill any leftover sing-box processes
        let cleanup = Process()
            cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            cleanup.arguments = ["-e", "do shell script \"pkill -f sing-box; sleep 0.5\" with administrator privileges"]
        try? cleanup.run()
            cleanup.waitUntilExit()

        guard let singboxPath = findSingBox() else {
            connectionState = .error("sing-box не найден")
            return
        }

        guard PrefsManager.shared.getSingboxConfig() != nil else {
            connectionState = .error("Нет конфигурации. Добавьте подписку.")
            return
        }

        let configFile = PrefsManager.shared.singboxConfigPath.path

        do {
            // Use osascript to run sing-box with admin privileges (needed for TUN)
            // We wrap it in a background shell so it keeps running
            let script = "do shell script \"\(singboxPath) run -c '\(configFile)' > /tmp/singbox.log 2>&1 & echo $!\" with administrator privileges"

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            try proc.run()
            proc.waitUntilExit()

            // Get the PID of the background sing-box process
            let pidData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let pidString = String(data: pidData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if proc.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Ошибка запуска"
                connectionState = .error(errMsg)
                return
            }

            // Wait for sing-box to initialize
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s

            // Check if sing-box is running by querying clash API
            let isRunning = await checkClashAPI()

            if isRunning {
                connectionState = .connected
                connectTime = Date()
                startTimers()

                // Monitor the process via PID
                if let pid = Int32(pidString) {
                    monitorPID(pid)
                }
            } else {
                // Read log for error details
                let log = (try? String(contentsOfFile: "/tmp/singbox.log", encoding: .utf8)) ?? ""
                let lastLine = log.components(separatedBy: "\n").filter { !$0.isEmpty }.last ?? "sing-box не запустился"
                connectionState = .error(lastLine)
            }
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    private func checkClashAPI() async -> Bool {
        guard let url = URL(string: "\(clashAPIBase)/version") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func monitorPID(_ pid: Int32) {
        Task.detached { [weak self] in
            // Poll every 2 seconds to check if process is still alive
            while true {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let alive = kill(pid, 0) == 0
                if !alive {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        if self.connectionState == .connected {
                            let log = (try? String(contentsOfFile: "/tmp/singbox.log", encoding: .utf8)) ?? ""
                            let lastLine = log.components(separatedBy: "\n").filter { !$0.isEmpty }.last ?? "sing-box завершился неожиданно"
                            self.connectionState = .error(lastLine)
                            self.stopTimers()
                        }
                    }
                    break
                }
            }
        }
    }

    func disconnect() {
        guard connectionState == .connected || connectionState == .connecting else { return }
        connectionState = .disconnecting
        stopTimers()

        // Kill sing-box by name (it runs as root via sudo)
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        killProc.arguments = ["-e", "do shell script \"pkill -f sing-box\" with administrator privileges"]
        try? killProc.run()
        killProc.waitUntilExit()

        process = nil
        connectionState = .disconnected
        trafficStats = TrafficStats()
        elapsedTime = 0
        connectTime = nil
    }

    // MARK: - Timers

    private func startTimers() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollTrafficStats()
            }
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.connectTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimers() {
        statsTimer?.invalidate()
        statsTimer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Traffic Stats

    private func pollTrafficStats() async {
        guard let connURL = URL(string: "\(clashAPIBase)/connections") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: connURL)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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
        } catch {}
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
