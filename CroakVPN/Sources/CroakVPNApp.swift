import SwiftUI
import ServiceManagement

@main
struct CroakVPNApp: App {
    @StateObject private var vm = AppViewModel()
    @StateObject private var launchManager = LaunchAtLoginManager()

    init() {
        // Снимаем карантин со всего бандла при первом запуске
        // Без этого macOS блокирует sing-box внутри .app после скачивания из интернета
        Self.removeQuarantine()
    }

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .environmentObject(launchManager)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 560)

        // Menubar icon
        MenuBarExtra {
            MenuBarView(vm: vm, launchManager: launchManager)
        } label: {
            Image(systemName: menuBarIcon)
        }
    }

    private var menuBarIcon: String {
        switch vm.connectionState {
        case .connected:    return "shield.checkered"
        case .connecting:   return "shield.slash"
        case .error:        return "exclamationmark.shield"
        default:            return "shield"
        }
    }

    /// Снимает com.apple.quarantine с бандла и sing-box бинарника
    private static func removeQuarantine() {
        let bundlePath = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-dr", "com.apple.quarantine", bundlePath]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        // Также гарантируем +x на sing-box
        if let singbox = Bundle.main.resourceURL?.appendingPathComponent("sing-box").path {
            chmod(singbox, 0o755)
        }
    }
}

// MARK: - Launch at Login Manager

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool = false

    init() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
                isEnabled = false
            } else {
                try SMAppService.mainApp.register()
                isEnabled = true
            }
        } catch {
            // Если не удалось — сбрасываем состояние по факту
            isEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }
}
