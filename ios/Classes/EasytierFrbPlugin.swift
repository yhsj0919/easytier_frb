import Flutter
import NetworkExtension

/// Flutter 宿主仅管理系统 VPN；EasyTier 核心由独立扩展持有。
public final class EasytierFrbPlugin: NSObject, FlutterPlugin {
    private var manager: NETunnelProviderManager?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "easytier_flutter/ios_vpn", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(EasytierFrbPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let flutterResult = result
        let result: FlutterResult = { value in
            DispatchQueue.main.async { flutterResult(value) }
        }
        loadManager { error in
            if let error = error {
                result(self.failure(error))
                return
            }
            guard let manager = self.manager else { return }
            switch call.method {
            case "configure":
                guard let arguments = call.arguments as? [String: Any],
                      let toml = arguments["toml"] as? String, !toml.isEmpty,
                      let bundleID = Bundle.main.bundleIdentifier else {
                    result(FlutterError(code: "invalidConfig", message: "请提供完整 TOML 配置。", details: nil))
                    return
                }
                let config = NETunnelProviderProtocol()
                // 正式宿主可在 Info.plist 指定自己的扩展 Bundle ID。
                config.providerBundleIdentifier = Bundle.main.object(forInfoDictionaryKey: "EasyTierTunnelBundleIdentifier") as? String ?? "\(bundleID).EasyTierTunnel"
                config.serverAddress = "EasyTier"
                config.providerConfiguration = ["toml": toml]
                manager.protocolConfiguration = config
                manager.localizedDescription = "EasyTier 组网"
                manager.isEnabled = true
                // 系统首次保存时申请 VPN 权限，不保存到普通日志或公开文件。
                manager.saveToPreferences { error in
                    if let error = error { result(self.failure(error)); return }
                    manager.loadFromPreferences { error in
                        result(error.map(self.failure))
                    }
                }
            case "start":
                guard manager.protocolConfiguration != nil else {
                    result(FlutterError(code: "missingConfig", message: "请先保存组网配置。", details: nil))
                    return
                }
                do {
                    try manager.connection.startVPNTunnel()
                    // 这里只表示启动请求已提交，connected 状态才表示系统连接成功。
                    result(nil)
                } catch { result(self.failure(error)) }
            case "stop":
                manager.connection.stopVPNTunnel()
                result(nil)
            case "status":
                result(self.status(manager.connection.status))
            case "snapshot":
                guard manager.connection.status == .connected,
                      let session = manager.connection as? NETunnelProviderSession else {
                    result(FlutterError(code: "notConnected", message: "系统 VPN 尚未连接。", details: nil))
                    return
                }
                do {
                    try session.sendProviderMessage(Data("snapshot".utf8)) { data in
                        guard let data = data, let json = String(data: data, encoding: .utf8) else {
                            result(FlutterError(code: "emptyResponse", message: "VPN 扩展未返回状态。", details: nil))
                            return
                        }
                        result(json)
                    }
                } catch { result(self.failure(error)) }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func loadManager(completion: @escaping (Error?) -> Void) {
        if manager != nil { completion(nil); return }
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            guard error == nil else { completion(error); return }
            let bundleID = Bundle.main.object(forInfoDictionaryKey: "EasyTierTunnelBundleIdentifier") as? String ?? "\(Bundle.main.bundleIdentifier ?? "").EasyTierTunnel"
            self.manager = managers?.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleID
            } ?? NETunnelProviderManager()
            completion(nil)
        }
    }

    private func failure(_ error: Error) -> FlutterError {
        FlutterError(code: "iosVpnFailed", message: error.localizedDescription, details: nil)
    }

    private func status(_ value: NEVPNStatus) -> String {
        switch value {
        case .invalid: return "unconfigured"
        case .disconnected: return "stopped"
        case .connecting: return "starting"
        case .connected: return "running"
        case .reasserting: return "reconnecting"
        case .disconnecting: return "stopping"
        @unknown default: return "unknown"
        }
    }
}
