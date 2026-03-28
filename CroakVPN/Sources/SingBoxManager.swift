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
        var candidates: [String] = []

        // 1. Bundle.main.resourceURL (стандартный путь для ресурсов)
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("sing-box").path)
        }

        // 2. Рядом с исполняемым файлом приложения (Contents/MacOS/)
        if let execURL = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(execURL.appendingPathComponent("sing-box").path)
        }

        // 3. Contents/Resources/ напрямую через bundleURL
        let contentsResources = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/sing-box").path
        candidates.append(contentsResources)

        // 4. Системные пути (если пользователь установил вручную)
        candidates += ["/usr/local/bin/sing-box", "/opt/homebrew/bin/sing-box", "/usr/bin/sing-box"]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Логируем все проверенные пути для диагностики
        let checked = candidates.joined(separator: "\n  ")
        print("[CroakVPN] sing-box не найден. Проверены пути:\n  \(checked)")
        return nil
    }

    // MARK: - Shell

    private func shell(_ cmd: String) async -> (String, Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", cmd]
                let outPipe = Pipe()
                let errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                // Читаем данные ДО waitUntilExit, чтобы избежать deadlock при переполнении буфера
                var outData = Data()
                var errData = Data()
                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    outData.append(handle.availableData)
                }
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    errData.append(handle.availableData)
                }
                try? p.run()
                p.waitUntilExit()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // Дочитываем остаток
                outData.append(outPipe.fileHandleForReading.readDataToEndOfFile())
                errData.append(errPipe.fileHandleForReading.readDataToEndOfFile())
                let out = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let err = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // Возвращаем stdout, а если он пуст — stderr
                let result = out.isEmpty ? err : out
                cont.resume(returning: (result, p.terminationStatus))
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
        for i in 0..<20 {
            let timeout = i < 5 ? 1 : 2
            let (out, _) = await shell("curl -s --connect-timeout \(timeout) --max-time \(timeout) http://\(clashAPIBase)/version")
            if out.contains("sing-box") { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
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
            connectionState = .error("sing-box не найден в приложении. Переустановите CroakVPN.")
            return
        }

        // Убеждаемся что бинарник исполняемый и не заблокирован Gatekeeper
        await shell("chmod +x '\(singboxPath)'")
        await shell("xattr -dr com.apple.quarantine '\(singboxPath)' 2>/dev/null")

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
sudo /usr/bin/pkill -x sing-box 2>/dev/null
sleep 0.5
sudo '\(singboxPath)' run -c '\(configFile)' >'\(logFile)' 2>&1 &
sleep 1
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
            // Проверяем, жив ли процесс
            let (pgrep, _) = await shell("pgrep -x sing-box")
            let processAlive = !pgrep.isEmpty

            let log = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
            let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
            let fatal = lines.first { $0.contains("FATAL") || $0.contains("fatal") || $0.contains("error") || $0.contains("Error") }
            let lastLines = lines.suffix(3).joined(separator: "\n")

            let errorMsg: String
            if !log.isEmpty {
                errorMsg = stripAnsi(fatal ?? lastLines)
            } else if !processAlive {
                errorMsg = "sing-box завершился сразу. Проверьте конфигурацию или переустановите sing-box."
            } else {
                errorMsg = "sing-box не запустился (API недоступен). Попробуйте переподключиться."
            }
            connectionState = .error(errorMsg)
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
