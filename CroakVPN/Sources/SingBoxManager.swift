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
    private let sudoersFile = "/etc/sudoers.d/croakvpn"

    // MARK: - Find sing-box binary

    private func findSingBox() -> String? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("sing-box").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let paths = ["/usr/local/bin/sing-box", "/opt/homebrew/bin/sing-box", "/usr/bin/sing-box"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Shell

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

    // Запуск shell-скрипта с правами администратора через AppleScript
    @discardableResult
    private func runAsAdmin(_ scriptPath: String) async -> Int32 {
        let appleScript = "do shell script \"sh '\(scriptPath)'\" with administrator privileges"
        let asPath = NSTemporaryDirectory() + "croakvpn.applescript"
        try? appleScript.write(toFile: asPath, atomically: true, encoding: .utf8)
        let (_, status) = await shell("/usr/bin/osascript '\(asPath)'")
        return status
    }

    // MARK: - Sudoers (один раз навсегда)

    private var sudoersInstalled: Bool {
        FileManager.default.fileExists(atPath: sudoersFile)
    }

    /// Устанавливает sudoers — один запрос пароля, потом навсегда без пароля.
    /// Содержимое пишется через Swift напрямую в файл, без shell-экранирования.
    private func installSudoers(singboxPath: String) async -> Bool {
        let user = NSUserName()
        let sudoersContent = "Defaults:\(user) !requiretty\n\(user) ALL=(ALL) NOPASSWD: \(singboxPath), /usr/bin/pkill\n"

        // Пишем содержимое sudoers в tmp-файл — без экранирования
        let tmpSudoers = NSTemporaryDirectory() + "croakvpn_sudoers"
        guard (try? sudoersContent.write(toFile: tmpSudoers, atomically: true, encoding: .utf8)) != nil else {
            return false
        }

        // Shell-скрипт: копируем tmp -> /etc/sudoers.d/croakvpn и выставляем права
        let installScript = """
#!/bin/sh
cp '\(tmpSudoers)' '\(sudoersFile)'
chmod 440 '\(sudoersFile)'
chown root:wheel '\(sudoersFile)'
"""
        let installPath = NSTemporaryDirectory() + "croakvpn_install_sudoers.sh"
        guard (try? installScript.write(toFile: installPath, atomically: true, encoding: .utf8)) != nil else {
            return false
        }

        // Один запрос пароля
        let status = await runAsAdmin(installPath)
        return status == 0
    }

    // MARK: - API check

    private func checkAPI() async -> Bool {
        for _ in 0..<15 {
            let (out, _) = await shell("curl -s --connect-timeout 1 --max-time 1 http://\(clashAPIBase)/version")
            if out.contains("sing-box") { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    // MARK: - Connect

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

        // Первый запуск — устанавливаем sudoers (один запрос пароля)
        if !sudoersInstalled {
            let ok = await installSudoers(singboxPath: singboxPath)
            if !ok {
                connectionState = .disconnected
                return
            }
        }

        // Запуск sing-box через sudo — без пароля
        let startScript = """
#!/bin/sh
/usr/bin/pkill -x sing-box 2>/dev/null
sleep 0.3
sudo '\(singboxPath)' run -c '\(configFile)' > '\(logFile)' 2>&1 &
"""
        let startPath = NSTemporaryDirectory() + "croakvpn_start.sh"
        try? startScript.write(toFile: startPath, atomically: true, encoding: .utf8)
        await shell("chmod +x '\(startPath)'")
        await shell("sh '\(startPath)'")

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

    // MARK: - Disconnect

    func disconnect() {
        guard connectionState == .connected || connectionState == .connecting else { return }
        connectionState = .disconnecting
        stopTimers()

        Task {
            await shell("sudo /usr/bin/pkill -x sing-box 2>/dev/null")
            await MainActor.run {
                self.connectionState = .disconnected
                self.trafficStats = TrafficStats()
                self.elapsedTime = 0
                self.connectTime = nil
            }
        }
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

    // MARK: - Traffic stats

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

    // MARK: - Helpers

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
