import SwiftUI

@main
struct CroakVPNApp: App {
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 560)

        // Menubar icon
        MenuBarExtra {
            MenuBarView(vm: vm)
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
