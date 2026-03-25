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

    /// Looks for sing-box in the app bundle first, then in common system paths.
    private func findSingBox() -> String? {
        // 1. Bundled binary inside .app/Contents/Resources/sing-box
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("sing-box").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }

        // 2. Common system paths
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
            connectionState = .error("sing-box не найден. Поместите бинарник в Resources приложения или установите через brew install sing-box")
            return
        }

        guard PrefsManager.shared.getSingboxConfig() != nil else {
            connectionState = .error("Нет конфигурации. Добавьте подписку.")
            return
        }

        let configFile = PrefsManager.shared.singboxConfigPath.path

        do {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: singboxPath)
            proc.arguments = ["run", "-c", configFile]

            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = FileHandle.nullDevice

            proc.terminationHandler = { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.connectionState == .connected || self.connectionState == .connecting {
                        // Unexpected termination
                        let errData = errPipe.fileHandleForReading.availableData
                        let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        self.connectionState = .error(errMsg.isEmpty ? "sing-box завершился неожиданно" : errMsg)
                        self.stopTimers()
                    }
                }
            }

            try proc.run()
            self.process = proc

            // Wait a bit for sing-box to start, then verify via clash API
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s

            if proc.isRunning {
                connectionState = .connected
                connectTime = Date()
                startTimers()
            } else {
                connectionState = .error("sing-box не запустился")
            }
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func disconnect() {
        guard connectionState == .connected || connectionState == .connecting else { return }
        connectionState = .disconnecting

        stopTimers()

        if let proc = process, proc.isRunning {
            proc.terminate()
            // Give it a moment to exit gracefully
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if proc.isRunning {
                    proc.interrupt()
                }
            }
        }
        process = nil
        connectionState = .disconnected
        trafficStats = TrafficStats()
        elapsedTime = 0
        connectTime = nil
    }

    // MARK: - Timers

    private func startTimers() {
        // Poll traffic stats every second via clash API
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollTrafficStats()
            }
        }

        // Update elapsed time every second
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

    // MARK: - Traffic Stats via Clash API

    private func pollTrafficStats() async {
        guard URL(string: "\(clashAPIBase)/traffic") != nil else { return }

        // Clash API /traffic is a streaming endpoint. We do a quick GET to /connections instead.
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
        } catch {
            // Clash API not responding — ignore silently
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
        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    // MARK: - Formatted elapsed time

    var formattedElapsed: String {
        let total = Int(elapsedTime)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
