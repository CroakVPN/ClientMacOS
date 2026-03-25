import SwiftUI

struct ContentView: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.09, green: 0.10, blue: 0.13)
                .ignoresSafeArea()

            if vm.hasSubscription {
                MainView(vm: vm)
            } else {
                SubscriptionSetupView(vm: vm)
            }
        }
        .frame(width: 360, height: 560)
        .sheet(isPresented: $vm.showSettings) {
            SettingsView(vm: vm)
        }
    }
}

// MARK: - Main Connected View

struct MainView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView(onSettings: { vm.showSettings = true })

            Spacer()

            // Connect Button
            ConnectButton(state: vm.connectionState) {
                Task { await vm.toggleConnection() }
            }

            // Status Text
            Text(vm.connectionState.displayText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(statusColor)
                .padding(.top, 16)

            Spacer()

            // Traffic Stats
            TrafficStatsView(stats: vm.trafficStats)
                .padding(.bottom, 8)

            // Timer
            Text("Время: \(vm.formattedElapsed)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.gray)
                .padding(.bottom, 16)

            // Footer
            FooterView()
                .padding(.bottom, 12)
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

// MARK: - Connect Button (big circle like Windows version)

struct ConnectButton: View {
    let state: ConnectionState
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(ringColor.opacity(0.3), lineWidth: 4)
                    .frame(width: 130, height: 130)

                // Filled circle
                Circle()
                    .fill(fillColor)
                    .frame(width: 110, height: 110)
                    .shadow(color: fillColor.opacity(0.4), radius: 12, x: 0, y: 4)

                // Icon
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
