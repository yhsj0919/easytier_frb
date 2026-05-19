import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android 系统 VpnService（MethodChannel + EventChannel）。
class PlatformVpn {
  PlatformVpn._();

  static const _methodChannel = MethodChannel('easytier_flutter/vpn');
  static const _eventChannel = EventChannel('easytier_flutter/vpn_events');

  static Stream<Map<String, dynamic>>? _events;

  static bool get needsSystemVpn => Platform.isAndroid;

  static Stream<Map<String, dynamic>> get vpnEvents {
    _events ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _events!;
  }

  static Stream<Map<String, dynamic>> get onVpnServiceStart => vpnEvents
      .where((e) => e['event'] == 'vpn_service_start')
      .map((e) => Map<String, dynamic>.from(e['data'] as Map));

  static Stream<Map<String, dynamic>> get onVpnServiceStop => vpnEvents
      .where((e) => e['event'] == 'vpn_service_stop')
      .map((e) => Map<String, dynamic>.from(e['data'] as Map));

  /// 请求 VPN 权限；返回 true 表示已授权。
  static Future<bool> prepareVpn() async {
    if (!Platform.isAndroid) return true;
    final ok = await _methodChannel.invokeMethod<bool>('prepareVpn');
    return ok ?? false;
  }

  /// 启动系统 VPN（不传 TOML）。
  static Future<void> startVpn({
    required String configId,
    required String ipv4Addr,
    List<String> routes = const [],
    int mtu = 1300,
    String? dns,
  }) async {
    if (!Platform.isAndroid) return;
    await _methodChannel.invokeMethod<void>('startVpn', {
      'configId': configId,
      'ipv4Addr': ipv4Addr,
      'routes': routes,
      'mtu': mtu,
      if (dns != null && dns.isNotEmpty) 'dns': dns,
    });
  }

  static Future<void> stopVpn() async {
    if (!Platform.isAndroid) return;
    await _methodChannel.invokeMethod<void>('stopVpn');
  }

  static Future<String?> getDeviceName() async {
    if (!Platform.isAndroid) return null;
    return _methodChannel.invokeMethod<String>('getDeviceName');
  }

  /// 桌面端使用进程内 FRB（`rust_lib_easytier_frb`），不 spawn `easytier-core`。
  static bool get usesInProcessCore =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// 当前平台 TUN / VPN 前置说明（无 `easytier-core.exe` 路径要求）。
  static String get platformRequirements {
    if (Platform.isAndroid) {
      return 'Android 使用系统 VpnService 提供 TUN fd；EasyTier 在 Flutter 进程内运行。';
    }
    if (Platform.isWindows) {
      return 'Windows（进程内 Rust）：\n'
          '  1. 构建时 cargokit 会打包 wintun.dll、Packet.dll（来自 easytier git third_party）\n'
          '  2. 不需要也不嵌入 easytier-core.exe\n'
          '  3. 启用 TUN 时请以管理员身份运行 example\n'
          '  4. 或配置 no_tun / use_smoltcp 做用户态模式';
    }
    if (Platform.isMacOS) {
      return 'macOS（进程内 Rust）：\n'
          '  1. 不嵌入 easytier-core 子进程\n'
          '  2. 开发期 TUN 通常需要 root 或 Network Extension 权限';
    }
    if (Platform.isLinux) {
      return 'Linux（进程内 Rust）：\n'
          '  1. 不嵌入 easytier-core 子进程\n'
          '  2. TUN 需要 root 或 CAP_NET_ADMIN，且 /dev/net/tun 可用';
    }
    return '未知平台';
  }

  /// Windows：检查应用目录旁是否有 cargokit 打包的 wintun.dll。
  static Future<bool> checkWintunNextToApp() async {
    if (!Platform.isWindows) return true;
    final exe = Platform.resolvedExecutable;
    final sep = Platform.pathSeparator;
    final dir = exe.contains(sep)
        ? exe.substring(0, exe.lastIndexOf(sep))
        : '.';
    return File('$dir${sep}wintun.dll').exists();
  }
}
