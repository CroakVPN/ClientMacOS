import Foundation

// MARK: - Connection State

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)
}

extension ConnectionState {
    var displayText: String {
        switch self {
        case .connected:      return "Защищено"
        case .connecting:     return "Подключение..."
        case .disconnecting:  return "Отключение..."
        case .disconnected:   return "Не подключено"
        case .error(let msg): return "Ошибка: \(msg)"
        }
    }

    var isActive: Bool {
        switch self {
        case .connected, .connecting, .disconnecting: return true
        default: return false
        }
    }
}

// MARK: - Traffic Stats

struct TrafficStats: Equatable {
    var downloadSpeed: String = "0 B/s"
    var uploadSpeed: String = "0 B/s"
    var totalDownload: Int64 = 0
    var totalUpload: Int64 = 0
}

// MARK: - Server Config (parsed from vless:// URI)

struct ServerConfig: Identifiable, Equatable {
    let id = UUID()
    var `protocol`: String = "vless"
    var uuid: String = ""
    var address: String = ""
    var port: Int = 443
    var flow: String?
    var security: String?
    var sni: String?
    var fingerprint: String?
    var publicKey: String?
    var shortId: String?
    var serverName: String?
    var network: String? = "tcp"
}
