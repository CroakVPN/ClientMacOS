import SwiftUI
import ServiceManagement

@main
struct CroakVPNApp: App {
    @StateObject private var vm = AppViewModel()
    @StateObject private var launchManager = LaunchAtLoginManager()

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
