import Foundation
import Network
import NetworkExtension

// 在 GitHub Mac runner 上验证纯设置逻辑，不把它当作 iPhone VPN 真机测试。
func check(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

func rejects(_ cidr: String) {
    do {
        _ = try TunnelIPv6Address(cidr)
        fatalError("应拒绝无效 IPv6 配置")
    } catch { }
}

let subnet = try TunnelIPv6Address("fd12:3456:789a:bcde::1234/64")
check(subnet.network == IPv6Address("fd12:3456:789a:bcde::")!.debugDescription, "IPv6 /64 网段错误")
check(subnet.route.destinationNetworkPrefixLength.intValue == 64, "系统前缀错误")
let host = try TunnelIPv6Address("fd12::1234/128")
check(host.address == host.network, "IPv6 /128 不应修改地址")
let all = try TunnelIPv6Address("fd12::1234/0")
check(all.network == IPv6Address("::")!.debugDescription, "IPv6 /0 应为默认路由")
let partial = try TunnelIPv6Address("fd12:3456:789a:bcde:ffff::/73")
check(partial.network == IPv6Address("fd12:3456:789a:bcde:ff80::")!.debugDescription, "非整字节前缀错误")
rejects("fd12::/129")
rejects("fd12::/-1")
rejects("not-an-address/64")

let dns = try makeTunnelDNS(enabled: true, server: "100.100.100.101", zone: "custom.net.")!
check(dns.matchDomains == ["custom.net"], "DNS 应只接管指定组网域名")
check(dns.searchDomains == ["custom.net"], "DNS 搜索域错误")
check(dns.servers == ["100.100.100.101"], "DNS 地址错误")
check(try makeTunnelDNS(enabled: false, server: "", zone: "") == nil, "禁用 DNS 时不应接管系统")
print("IPv6 掩码与 DNS 设置检查通过。")
