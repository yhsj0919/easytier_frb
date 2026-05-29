import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android 系统 [VpnService] 的 MethodChannel / EventChannel 封装。
///
/// 桌面端方法多为空操作或直接返回默认值。
class PlatformVpn {
  PlatformVpn._();

  static const _methodChannel = MethodChannel('easytier_flutter/vpn');
  static const _eventChannel = EventChannel('easytier_flutter/vpn_events');

  static Stream<Map<String, dynamic>>? _events;

  /// 当前平台是否必须通过系统 VPN 提供 TUN（仅 Android 为 true）。
  static bool get needsSystemVpn => Platform.isAndroid;

  /// 全部 VPN 相关原生事件流（广播）。
  static Stream<Map<String, dynamic>> get vpnEvents {
    _events ??= _eventChannel.receiveBroadcastStream().map((event) => Map<String, dynamic>.from(event as Map));
    return _events!;
  }

  /// VpnService 已建立并返回 TUN `fd` 时触发。
  static Stream<Map<String, dynamic>> get onVpnServiceStart => vpnEvents.where((e) => e['event'] == 'vpn_service_start').map((e) => Map<String, dynamic>.from(e['data'] as Map));

  /// VpnService 已停止时触发。
  static Stream<Map<String, dynamic>> get onVpnServiceStop => vpnEvents.where((e) => e['event'] == 'vpn_service_stop').map((e) => Map<String, dynamic>.from(e['data'] as Map));

  /// 请求 VPN 权限；非 Android 恒为 `true`。
  static Future<bool> prepareVpn() async {
    if (!Platform.isAndroid) return true;
    final ok = await _methodChannel.invokeMethod<bool>('prepareVpn');
    return ok ?? false;
  }

  /// 启动系统 VPN（地址、路由、MTU）；非 Android 无操作。
  static Future<void> startVpn({required String configId, required String ipv4Addr, List<String> routes = const [], int mtu = 1300, String? dns}) async {
    if (!Platform.isAndroid) return;
    await _methodChannel.invokeMethod<void>('startVpn', {'configId': configId, 'ipv4Addr': ipv4Addr, 'routes': routes, 'mtu': mtu, if (dns != null && dns.isNotEmpty) 'dns': dns});
  }

  /// 停止系统 VPN；非 Android 无操作。
  static Future<void> stopVpn() async {
    if (!Platform.isAndroid) return;
    await _methodChannel.invokeMethod<void>('stopVpn');
  }

  /// 获取 Android 设备名（用于自动填充 hostname）；非 Android 返回 `null`。
  static Future<String?> getDeviceName() async {
    if (!Platform.isAndroid) return null;
    return _methodChannel.invokeMethod<String>('getDeviceName');
  }

  /// 桌面端是否在 Flutter 进程内直接运行 Rust 核心。
  static bool get usesInProcessCore => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// 面向用户的当前平台组网要求说明文案。
  static String get platformRequirements {
    if (Platform.isAndroid) {
      return 'Android 使用系统 VpnService 提供 TUN fd；EasyTier 在 Flutter 进程内运行。';
    }
    if (Platform.isWindows) {
      return 'Windows（进程内 Rust）：\n'
          '  1. 构建时 cargokit 会打包 wintun.dll、Packet.dll\n'
          '  2. 启用 TUN 时请以管理员身份运行\n'
          '  3. 或配置 no_tun / use_smoltcp 做用户态模式';
    }
    if (Platform.isMacOS) {
      return 'macOS（进程内 Rust）：TUN 通常需要 root 或 Network Extension 权限。';
    }
    if (Platform.isLinux) {
      return 'Linux（进程内 Rust）：TUN 需要 root 或 CAP_NET_ADMIN。';
    }
    return '未知平台';
  }

  /// 检查可执行文件同目录是否存在 `wintun.dll`；非 Windows 恒为 `true`。
  static Future<bool> checkWintunNextToApp() async {
    if (!Platform.isWindows) return true;
    final exe = Platform.resolvedExecutable;
    final sep = Platform.pathSeparator;
    final dir = exe.contains(sep) ? exe.substring(0, exe.lastIndexOf(sep)) : '.';
    return File('$dir${sep}wintun.dll').exists();
  }
}
