import Foundation

/// Parses vless://uuid@host:port?params#fragment URIs
enum VLESSParser {

    static func parse(_ uri: String) -> ServerConfig? {
        guard uri.lowercased().hasPrefix("vless://") else { return nil }

        do {
            let stripped = String(uri.dropFirst("vless://".count))

            // Split fragment
            let fragmentIdx = stripped.firstIndex(of: "#")
            let mainPart = fragmentIdx.map { String(stripped[stripped.startIndex..<$0]) } ?? stripped
            let fragment = fragmentIdx.map { idx -> String in
                let afterHash = stripped.index(after: idx)
                return String(stripped[afterHash...]).removingPercentEncoding ?? String(stripped[afterHash...])
            }

            // Split query
            let queryIdx = mainPart.firstIndex(of: "?")
            let authHost = queryIdx.map { String(mainPart[mainPart.startIndex..<$0]) } ?? mainPart
            let queryString = queryIdx.map { idx -> String in
                let afterQ = mainPart.index(after: idx)
                return String(mainPart[afterQ...])
            } ?? ""

            // Parse uuid@host:port
            guard let atIdx = authHost.firstIndex(of: "@") else { return nil }
            let uuid = String(authHost[authHost.startIndex..<atIdx])
            let hostPort = String(authHost[authHost.index(after: atIdx)...])

            let (address, port) = parseHostPort(hostPort)
            let parameters = parseQueryParams(queryString)

            return ServerConfig(
                protocol: "vless",
                uuid: uuid,
                address: address,
                port: port,
                flow: parameters["flow"],
                security: parameters["security"],
                sni: parameters["sni"],
                fingerprint: parameters["fp"],
                publicKey: parameters["pbk"],
                shortId: parameters["sid"],
                serverName: fragment,
                network: parameters["type"] ?? "tcp"
            )
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private static func parseHostPort(_ hostPort: String) -> (String, Int) {
        if hostPort.hasPrefix("[") {
            // IPv6: [::1]:port
            guard let closeBracket = hostPort.firstIndex(of: "]") else {
                return (hostPort, 443)
            }
            let address = String(hostPort[hostPort.index(after: hostPort.startIndex)..<closeBracket])
            let rest = String(hostPort[hostPort.index(after: closeBracket)...])
            let port: Int
            if rest.hasPrefix(":"), let p = Int(rest.dropFirst()) {
                port = p
            } else {
                port = 443
            }
            return (address, port)
        }

        let parts = hostPort.split(separator: ":", maxSplits: 1).map(String.init)
        let addr = parts[0]
        let prt = parts.count > 1 ? (Int(parts[1]) ?? 443) : 443
        return (addr, prt)
    }

    private static func parseQueryParams(_ query: String) -> [String: String] {
        guard !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                let key = kv[0].removingPercentEncoding ?? kv[0]
                let val = kv[1].removingPercentEncoding ?? kv[1]
                result[key] = val
            }
        }
        return result
    }
}
