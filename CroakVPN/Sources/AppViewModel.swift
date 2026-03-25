import Foundation
import SwiftUI
import Combine

@MainActor
final class AppViewModel: ObservableObject {

    @Published var connectionState: ConnectionState = .disconnected
    @Published var trafficStats = TrafficStats()
    @Published var elapsedTime: TimeInterval = 0
    @Published var hasSubscription: Bool = false
    @Published var subscriptionURL: String = ""
    @Published var isLoading = false
    @Published var showSettings = false
    @Published var errorMessage: String?

    private let prefs = PrefsManager.shared
    private let singbox = SingBoxManager.shared
    private let repo = SubscriptionRepo.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        hasSubscription = prefs.hasSubscription
        subscriptionURL = prefs.subscriptionUrl ?? ""

        // Observe SingBoxManager
        singbox.$connectionState
            .receive(on: RunLoop.main)
            .assign(to: &$connectionState)

        singbox.$trafficStats
            .receive(on: RunLoop.main)
            .assign(to: &$trafficStats)

        singbox.$elapsedTime
            .receive(on: RunLoop.main)
            .assign(to: &$elapsedTime)
    }

    var formattedElapsed: String { singbox.formattedElapsed }

    // MARK: - Subscription

    func addSubscription() async {
        let url = subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            errorMessage = "Введите URL подписки"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let configs = try await repo.fetchAndParse(url: url)
            guard !configs.isEmpty else {
                throw CroakError.noConfigs
            }

            let singboxConfig = ConfigGenerator.generate(configs)
            prefs.saveSubscription(url: url, singboxConfig: singboxConfig)
            hasSubscription = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshSubscription() async {
        guard let url = prefs.subscriptionUrl else { return }
        subscriptionURL = url
        await addSubscription()
    }

    func clearSubscription() {
        singbox.disconnect()
        prefs.clearSubscription()
        hasSubscription = false
        subscriptionURL = ""
    }

    // MARK: - Connection

    func toggleConnection() async {
        switch connectionState {
        case .disconnected, .error:
            await singbox.connect()
        case .connected:
            singbox.disconnect()
        default:
            break
        }
    }
}
