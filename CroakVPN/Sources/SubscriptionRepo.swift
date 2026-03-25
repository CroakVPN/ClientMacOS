import Foundation

/// Fetches Marzban subscription URL and parses VLESS configs.
/// Marzban returns base64-encoded list of vless:// URIs.
final class SubscriptionRepo {

    static let shared = SubscriptionRepo()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "CroakVPN/1.0"]
        return URLSession(configuration: config)
    }()

    func fetchAndParse(url urlString: String) async throws -> [ServerConfig] {
        guard let url = URL(string: urlString) else {
            throw CroakError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CroakError.serverError
        }

        let body = String(data: data, encoding: .utf8) ?? ""

        // Marzban returns base64-encoded content
        let decoded: String
        if let decodedData = Data(base64Encoded: body.trimmingCharacters(in: .whitespacesAndNewlines)) {
            decoded = String(data: decodedData, encoding: .utf8) ?? body
        } else {
            decoded = body
        }

        return decoded
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { VLESSParser.parse($0) }
    }
}

// MARK: - Errors

enum CroakError: LocalizedError {
    case invalidURL
    case serverError
    case noConfigs
    case singboxNotFound
    case singboxFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Неверный URL подписки"
        case .serverError:         return "Ошибка сервера"
        case .noConfigs:           return "Сервера не найдены"
        case .singboxNotFound:     return "sing-box не найден"
        case .singboxFailed(let m): return "sing-box: \(m)"
        }
    }
}
