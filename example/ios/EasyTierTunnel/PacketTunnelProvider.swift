import Foundation
import NetworkExtension

/// 系统 VPN 扩展入口。核心应在本扩展进程运行，不在 Flutter 页面进程运行。
final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // 第一阶段仅验证扩展能编译、被嵌入应用。不能把模板启动当作组网成功。
        // 后续：读取 TOML，启动 Rust，配置 IP/路由，接通 packetFlow 后再返回成功。
        completionHandler(NSError(
            domain: "easytier_frb.ios",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "iOS VPN 扩展模板已就绪，Rust 核心和数据通道尚未接入。"]
        ))
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        // 后续在这里停止扩展持有的核心实例和监听，再通知系统停止完成。
        completionHandler()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        // 宿主与扩展是两个进程；后续通过此入口查询核心快照。
        let response = ["status": "notImplemented", "message": "VPN 核心尚未接入"]
        completionHandler?(try? JSONSerialization.data(withJSONObject: response))
    }
}
