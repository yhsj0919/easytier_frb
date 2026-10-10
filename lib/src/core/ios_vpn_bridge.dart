import 'package:flutter/services.dart';

/// iOS 宿主和系统 VPN 的内部通道，不直接在页面进程启动核心。
///
/// 由 iOS 引擎统一使用，页面继续调用 EasyTier 的公共接口。
final class IosVpnBridge {
  IosVpnBridge._();

  static const _channel = MethodChannel('easytier_flutter/ios_vpn');

  static Future<void> configure(String toml) =>
      _channel.invokeMethod<void>('configure', {'toml': toml});

  static Future<void> start() => _channel.invokeMethod<void>('start');

  static Future<void> stop() => _channel.invokeMethod<void>('stop');

  static Future<String> status() async =>
      (await _channel.invokeMethod<String>('status'))!;

  static Future<String> snapshot() async =>
      (await _channel.invokeMethod<String>('snapshot'))!;
}
