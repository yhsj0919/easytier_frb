import Foundation
import NetworkExtension
import Darwin

/// 使用公开 packetFlow 接口，核心运行在独立 VPN 扩展进程。
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let queue = DispatchQueue(label: "easytier.tunnel")
    private var instanceID = ""
    private var sockets: [Int32] = [-1, -1]
    private var reader: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var manualRoutes: [String]?
    private var mtu = 1380
    private var ipv6CIDR: String?
    private var dnsEnabled = false
    private var dnsServer = ""
    private var dnsZone = ""
    private var settingsKey = ""
    private var applying = false
    private var generation = 0

    private func failure(_ message: String) -> NSError {
        NSError(domain: "easytier_frb.ios", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func core(_ request: [String: Any]) throws -> Any {
        let input = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        guard let pointer = input.withCString({ et_ios_request($0) }) else { throw failure("核心未返回结果") }
        defer { et_ios_free(pointer) }
        let response = try JSONSerialization.jsonObject(with: Data(String(cString: pointer).utf8)) as! [String: Any]
        guard response["ok"] as? Bool == true else { throw failure(response["error"] as? String ?? "核心调用失败") }
        return response["value"] ?? NSNull()
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        queue.async {
            self.generation += 1
            do {
                guard let config = self.protocolConfiguration as? NETunnelProviderProtocol,
                      let toml = config.providerConfiguration?["toml"] as? String else { throw self.failure("请先保存 TOML") }
                let started = try self.core(["method": "start", "toml": toml]) as! [String: Any]
                self.instanceID = started["id"] as! String
                self.manualRoutes = started["manual_routes"] as? [String]
                self.mtu = started["mtu"] as? Int ?? 1380
                self.ipv6CIDR = started["ipv6"] as? String
                self.dnsEnabled = started["dns_enabled"] as? Bool ?? false
                self.dnsServer = started["dns_server"] as? String ?? ""
                self.dnsZone = started["dns_zone"] as? String ?? ""
                self.waitForAddress(Date().addingTimeInterval(30), self.generation, completionHandler)
            } catch { self.cleanup(); completionHandler(error) }
        }
    }

    private func snapshot() throws -> [String: Any] {
        let value = try core(["method": "snapshot", "id": instanceID]) as! [String: Any]
        if let error = value["error_msg"] as? String, !error.isEmpty { throw failure(error) }
        return value
    }

    private func waitForAddress(_ deadline: Date, _ generation: Int, _ completion: @escaping (Error?) -> Void) {
        guard generation == self.generation else { completion(failure("启动已取消")); return }
        do {
            let value = try snapshot()
            if let address = value["virtual_ipv4_host"] as? String, !address.isEmpty {
                updateSettings(value) { error in
                    guard generation == self.generation else { completion(self.failure("启动已取消")); return }
                    do {
                        if let error = error { throw error }
                        try self.connectPackets()
                        self.startUpdates()
                        completion(nil)
                    } catch { self.cleanup(); completion(error) }
                }
            } else {
                guard Date() < deadline else { throw failure("等待虚拟 IPv4 超时") }
                queue.asyncAfter(deadline: .now() + 0.2) { self.waitForAddress(deadline, generation, completion) }
            }
        } catch { cleanup(); completion(error) }
    }

    private func route(_ cidr: String) throws -> NEIPv4Route {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = Int(parts[1]), (0...32).contains(prefix) else { throw failure("无效 IPv4 路由") }
        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        let text = [24, 16, 8, 0].map { String((mask >> $0) & 255) }.joined(separator: ".")
        let octets = parts[0].split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { throw failure("无效 IPv4 路由地址") }
        let address = octets.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } & mask
        let network = [24, 16, 8, 0].map { String((address >> $0) & 255) }.joined(separator: ".")
        return NEIPv4Route(destinationAddress: network, subnetMask: text)
    }

    private func updateSettings(_ value: [String: Any], completion: @escaping (Error?) -> Void) {
        do {
            guard let address = value["virtual_ipv4_host"] as? String,
                  let node = value["my_node_info"] as? [String: Any],
                  let inet = node["virtual_ipv4"] as? [String: Any],
                  let prefix = inet["network_length"] as? Int else { throw failure("核心未返回 IPv4 与掩码") }
            var cidrs = ["\(address)/\(prefix)"]
            if let manual = manualRoutes { cidrs += manual }
            else { for peer in value["routes"] as? [[String: Any]] ?? [] { cidrs += peer["proxy_cidrs"] as? [String] ?? [] } }
            if dnsEnabled { cidrs.append("\(dnsServer)/32") }
            cidrs = Array(Set(cidrs)).sorted()
            let ipv4CIDRs = cidrs.filter { !$0.contains(":") }
            var ipv6CIDRs = cidrs.filter { $0.contains(":") }
            if let ipv6 = ipv6CIDR { ipv6CIDRs.append(ipv6) }
            ipv6CIDRs = Array(Set(ipv6CIDRs)).sorted()
            let key = "\(address):\(prefix):\(cidrs):\(ipv6CIDR ?? ""): \(ipv6CIDRs):\(dnsEnabled):\(dnsServer):\(dnsZone):\(mtu)"
            if key == settingsKey { completion(nil); return }
            let ownRoute = try route("\(address)/\(prefix)")
            let ipv4 = NEIPv4Settings(addresses: [address], subnetMasks: [ownRoute.destinationSubnetMask])
            ipv4.includedRoutes = try ipv4CIDRs.map(route)
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
            settings.ipv4Settings = ipv4
            if let ipv6CIDR = ipv6CIDR {
                let own = try TunnelIPv6Address(ipv6CIDR)
                let ipv6 = NEIPv6Settings(addresses: [own.address], networkPrefixLengths: [NSNumber(value: own.prefix)])
                ipv6.includedRoutes = try ipv6CIDRs.map { try TunnelIPv6Address($0).route }
                settings.ipv6Settings = ipv6
            } else if !ipv6CIDRs.isEmpty {
                NSLog("EasyTier：本机未配置虚拟 IPv6，仅安装 IPv4 路由。")
            }
            settings.dnsSettings = try makeTunnelDNS(enabled: dnsEnabled, server: dnsServer, zone: dnsZone)
            settings.mtu = NSNumber(value: mtu)
            applying = true
            let generation = self.generation
            setTunnelNetworkSettings(settings) { error in
                self.queue.async {
                    guard generation == self.generation else { completion(self.failure("配置已取消")); return }
                    self.applying = false
                    if error == nil { self.settingsKey = key }
                    completion(error)
                }
            }
        } catch { completion(error) }
    }

    private func connectPackets() throws {
        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &sockets) == 0 else { throw failure("无法创建数据通道") }
        for fd in sockets {
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        }
        _ = try core(["method": "set_fd", "id": instanceID, "fd": sockets[0]])
        let source = DispatchSource.makeReadSource(fileDescriptor: sockets[1], queue: queue)
        source.setEventHandler { [weak self] in self?.receivePackets() }
        let ownedSockets = sockets
        source.setCancelHandler { for fd in ownedSockets { close(fd) } }
        reader = source
        source.resume()
        readPackets(generation)
    }

    private func readPackets(_ generation: Int) {
        packetFlow.readPackets { packets, protocols in
            self.queue.async {
                guard generation == self.generation, self.reader != nil else { return }
                for (packet, family) in zip(packets, protocols) {
                    // 核心要求 4 字节网络字节序的地址族头。
                    var header = family.uint32Value.bigEndian
                    var data = Data(bytes: &header, count: 4)
                    data.append(packet)
                    data.withUnsafeBytes { buffer in _ = send(self.sockets[1], buffer.baseAddress, buffer.count, 0) }
                }
                self.readPackets(generation)
            }
        }
    }

    private func receivePackets() {
        var bytes = [UInt8](repeating: 0, count: 65536)
        // 每批限制数量，让停止和控制消息也有机会执行。
        for _ in 0..<64 {
            let count = recv(sockets[1], &bytes, bytes.count, 0)
            if count <= 0 { return }
            if count < 5 { continue }
            let family = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            packetFlow.writePackets([Data(bytes[4..<count])], withProtocols: [NSNumber(value: family)])
        }
    }

    private func startUpdates() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 1, repeating: 1)
        source.setEventHandler { [weak self] in
            guard let self = self, !self.applying else { return }
            do { self.updateSettings(try self.snapshot()) { error in
                if let error = error { self.cancelTunnelWithError(error) }
            } } catch { self.cancelTunnelWithError(error) }
        }
        timer = source
        source.resume()
    }

    private func cleanup() {
        generation += 1
        timer?.cancel(); timer = nil
        _ = try? core(["method": "stop"])
        if let reader = reader { reader.cancel(); self.reader = nil }
        else { for fd in sockets where fd >= 0 { close(fd) } }
        sockets = [-1, -1]
        instanceID = ""; settingsKey = ""; applying = false
        ipv6CIDR = nil; dnsEnabled = false; dnsServer = ""; dnsZone = ""
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async { self.cleanup(); completionHandler() }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        queue.async {
            do { completionHandler?(try JSONSerialization.data(withJSONObject: self.snapshot())) }
            catch { completionHandler?(try? JSONSerialization.data(withJSONObject: ["error_msg": error.localizedDescription])) }
        }
    }
}
