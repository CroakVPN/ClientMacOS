import Foundation

enum ConfigGenerator {

    static func generate(_ configs: [ServerConfig]) -> String {
        var outbounds: [[String: Any]] = []
        var proxyTags: [String] = []
        var serverAddresses: Set<String> = []

        for (i, config) in configs.enumerated() {
            let tag = configs.count == 1 ? "proxy" : "proxy-\(i)"
            if !config.address.isEmpty { serverAddresses.insert(config.address) }

            var outbound: [String: Any] = [
                "type": config.protocol, "tag": tag,
                "server": config.address, "server_port": config.port, "uuid": config.uuid,
                "domain_resolver": "local"
            ]

            if let flow = config.flow, !flow.isEmpty { outbound["flow"] = flow }

            if config.security == "reality" || config.security == "tls" {
                var tls: [String: Any] = ["enabled": true]
                if let sni = config.sni, !sni.isEmpty { tls["server_name"] = sni }
                if let fp = config.fingerprint, !fp.isEmpty {
                    tls["utls"] = ["enabled": true, "fingerprint": fp]
                }
                if config.security == "reality" {
                    var reality: [String: Any] = ["enabled": true]
                    if let pk = config.publicKey { reality["public_key"] = pk }
                    if let sid = config.shortId { reality["short_id"] = sid }
                    tls["reality"] = reality
                }
                outbound["tls"] = tls
            }

            if let network = config.network, network != "tcp", !network.isEmpty {
                outbound["transport"] = ["type": network]
            }

            outbounds.append(outbound)
            if configs.count > 1 { proxyTags.append(tag) }
        }

        if configs.count > 1 {
            outbounds.append([
                "type": "urltest", "tag": "proxy", "outbounds": proxyTags,
                "url": "https://www.gstatic.com/generate_204", "interval": "1m", "tolerance": 50
            ])
        }

        outbounds.append(["type": "direct", "tag": "direct"])

        var routeRules: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"]
        ]

        if !serverAddresses.isEmpty {
            // Разделяем IP-адреса и доменные имена
            var ipCidrs: [String] = []
            var domains: [String] = []
            for addr in serverAddresses {
                if addr.contains(":") {
                    // IPv6
                    ipCidrs.append(addr.contains("/") ? addr : "\(addr)/128")
                } else if addr.allSatisfy({ $0.isNumber || $0 == "." || $0 == "/" }) {
                    // IPv4
                    ipCidrs.append(addr.contains("/") ? addr : "\(addr)/32")
                } else {
                    // Домен
                    domains.append(addr)
                }
            }
            if !ipCidrs.isEmpty {
                routeRules.append([
                    "ip_cidr": ipCidrs,
                    "action": "route", "outbound": "direct"
                ])
            }
            if !domains.isEmpty {
                routeRules.append([
                    "domain": domains,
                    "action": "route", "outbound": "direct"
                ])
            }
        }
        routeRules.append(["ip_is_private": true, "action": "route", "outbound": "direct"])

        let root: [String: Any] = [
            "log": ["level": "info", "timestamp": true],
            "experimental": [
                "clash_api": ["external_controller": "127.0.0.1:9090", "secret": ""]
            ],
            "dns": [
                "servers": [
                    ["tag": "remote", "type": "tls", "server": "8.8.8.8", "detour": "proxy"],
                    ["tag": "local", "type": "udp", "server": "1.1.1.1"]
                ],
                "rules": [["ip_is_private": true, "server": "local"]],
                "final": "remote",
                "strategy": "ipv4_only"
            ],
            "inbounds": [[
                "type": "tun", "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true, "strict_route": false, "stack": "system"
            ]],
            "outbounds": outbounds,
            "route": [
                "rules": routeRules,
                "auto_detect_interface": true,
                "final": "proxy",
                "default_domain_resolver": "local"
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
