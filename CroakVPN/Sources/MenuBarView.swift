import SwiftUI

struct MenuBarView: View {
    @ObservedObject var vm: AppViewModel

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

            // Open main window
            Button("Открыть CroakVPN") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title.contains("CroakVPN") || $0.isKeyWindow }) {
                    window.makeKeyAndOrderFront(nil)
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
