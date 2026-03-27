import SwiftUI

struct MenuBarView: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var launchManager: LaunchAtLoginManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                Text(vm.connectionState.displayText)
                    .font(.system(size: 13))
            }

            Divider()

            // Toggle connection
            Button(action: {
                Task { await vm.toggleConnection() }
            }) {
                Label(
                    vm.connectionState == .connected ? "Отключить" : "Подключить",
                    systemImage: vm.connectionState == .connected ? "stop.fill" : "play.fill"
                )
            }
            .disabled(!vm.hasSubscription)

            Divider()

            // Launch at login toggle
            Button(action: { launchManager.toggle() }) {
                Label(
                    launchManager.isEnabled ? "Автозапуск: вкл" : "Автозапуск: выкл",
                    systemImage: launchManager.isEnabled ? "checkmark.circle.fill" : "circle"
                )
            }

            Divider()

            // Open main window
            Button("Открыть CroakVPN") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if !window.title.contains("Item-0") {
                        window.makeKeyAndOrderFront(nil)
                        break
                    }
                }
            }

            Button("Выйти") {
                vm.singboxDisconnect()
                NSApp.terminate(nil)
            }
        }
        .padding(8)
    }

    private var statusDotColor: Color {
        switch vm.connectionState {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .error:        return .red
        default:            return .gray
        }
    }
}

// Extension to expose disconnect for quit
extension AppViewModel {
    func singboxDisconnect() {
        SingBoxManager.shared.disconnect()
    }
}
