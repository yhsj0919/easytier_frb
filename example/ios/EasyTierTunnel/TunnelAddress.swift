import Foundation
import Network
import NetworkExtension

/// 对 IPv6 地址和掩码进行统一解析，系统路由使用规范化后的网段地址。
struct TunnelIPv6Address {
    let address: String
    let prefix: Int
    let network: String

    init(_ cidr: String) throws {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = Int(parts[1]), (0...128).contains(prefix),
              let parsed = IPv6Address(String(parts[0])) else {
            throw NSError(domain: "easytier_frb.ios", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "无效 IPv6 地址或路由"])
        }
        var bytes = Array(parsed.rawValue)
        for index in bytes.indices {
            let bits = max(0, min(8, prefix - index * 8))
            bytes[index] &= bits == 0 ? 0 : UInt8.max << (8 - bits)
        }
        self.address = parsed.debugDescription
        self.prefix = prefix
        self.network = IPv6Address(Data(bytes))!.debugDescription
    }

    var route: NEIPv6Route {
        NEIPv6Route(destinationAddress: network, networkPrefixLength: NSNumber(value: prefix))
    }
}

/// 只接管组网域名；不使用空 matchDomains，避免影响其他域名解析。
func makeTunnelDNS(enabled: Bool, server: String, zone: String) throws -> NEDNSSettings? {
    guard enabled else { return nil }
    let domain = zone.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard IPv4Address(server) != nil, !domain.isEmpty else {
        throw NSError(domain: "easytier_frb.ios", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "核心未返回有效 DNS 配置"])
    }
    let dns = NEDNSSettings(servers: [server])
    dns.matchDomains = [domain]
    dns.searchDomains = [domain]
    dns.matchDomainsNoSearch = true
    return dns
}
