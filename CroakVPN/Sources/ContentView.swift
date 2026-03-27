import SwiftUI

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @StateObject private var updater = UpdateChecker()

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.13)
                .ignoresSafeArea()

            if vm.hasSubscription {
                MainView(vm: vm, updater: updater)
            } else {
                SubscriptionSetupView(vm: vm)
            }
        }
        .frame(width: 360, height: 560)
        .sheet(isPresented: $vm.showSettings) {
            SettingsView(vm: vm)
        }
        .onAppear {
            Task { await updater.checkForUpdates() }
        }
    }
}

// MARK: - Update Checker

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""

    private let currentVersion = "1.0"
    private let releasesURL = "https://api.github.com/repos/CroakVPN/ClientMacOS/releases/latest"

    func checkForUpdates() async {
        guard let url = URL(string: releasesURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                if version != currentVersion {
                    latestVersion = version
                    updateAvailable = true
                }
            }
        } catch {}
    }

    func openReleasePage() {
        if let url = URL(string: "https://github.com/CroakVPN/ClientMacOS/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Main Connected View

struct MainView: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                gradient: Gradient(colors: [
                    tintColor.opacity(0.18),
                    tintColor.opacity(0.06),
                    Color.clear
                ]),
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Update banner
                if updater.updateAvailable {
                    Button(action: { updater.openReleasePage() }) {
                        HStack {
                            Text("Доступна версия \(updater.latestVersion)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text("Скачать")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.20, green: 0.40, blue: 0.75))
                    }
                    .buttonStyle(.plain)
                }

                HeaderView(onSettings: { vm.showSettings = true })

                Spacer()

                ConnectButton(state: vm.connectionState) {
                    Task { await vm.toggleConnection() }
                }

                Text(vm.connectionState.displayText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(statusColor)
                    .padding(.top, 16)

                Spacer()

                TrafficStatsView(stats: vm.trafficStats)
                    .padding(.bottom, 8)

                Text("Время: \(vm.formattedElapsed)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.bottom, 16)

                FooterView()
                    .padding(.bottom, 12)
            }
        }
    }

    private var statusColor: Color {
        switch vm.connectionState {
        case .connected:    return Color(red: 0.30, green: 0.78, blue: 0.35)
        case .connecting, .disconnecting: return .yellow
        case .error:        return .red
        default:            return .gray
        }
    }

    private var tintColor: Color {
        switch vm.connectionState {
        case .connected:    return Color(red: 0.30, green: 0.78, blue: 0.35)
        case .connecting:   return Color(red: 0.85, green: 0.65, blue: 0.15)
        case .error:        return Color(red: 0.85, green: 0.25, blue: 0.25)
        default:            return Color(red: 0.35, green: 0.38, blue: 0.42)
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    var onSettings: () -> Void

    var body: some View {
        HStack {
            Text("CroakVPN")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}

// MARK: - Connect Button

struct ConnectButton: View {
    let state: ConnectionState
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.3), lineWidth: 4)
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(fillColor)
                    .frame(width: 110, height: 110)
                    .shadow(color: fillColor.opacity(0.4), radius: 12, x: 0, y: 4)
                iconView
            }
        }
        .buttonStyle(.plain)
        .disabled(state == .connecting || state == .disconnecting)
    }

    @ViewBuilder
    private var iconView: some View {
        switch state {
        case .connected:
            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white)
        case .connecting, .disconnecting:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(.white)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.white)
        default:
            Image(systemName: "power")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var fillColor: Color {
        switch state {
        case .connected:    return Color(red: 0.30, green: 0.78, blue: 0.35)
        case .connecting:   return Color(red: 0.85, green: 0.65, blue: 0.15)
        case .error:        return Color(red: 0.85, green: 0.25, blue: 0.25)
        default:            return Color(red: 0.35, green: 0.38, blue: 0.42)
        }
    }

    private var ringColor: Color {
        switch state {
        case .connected:    return Color(red: 0.30, green: 0.78, blue: 0.35)
        case .connecting:   return .yellow
        case .error:        return .red
        default:            return .gray
        }
    }
}

// MARK: - Traffic Stats

struct TrafficStatsView: View {
    let stats: TrafficStats

    var body: some View {
        HStack(spacing: 40) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                Text(stats.downloadSpeed)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Text("Загрузка")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            VStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                Text(stats.uploadSpeed)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Text("Отдача")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    var body: some View {
        Text("@croakvpnbot")
            .font(.system(size: 11))
            .foregroundColor(Color.gray.opacity(0.5))
    }
}
