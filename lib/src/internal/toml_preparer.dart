import 'dart:io';

import 'package:toml/toml.dart';
import 'package:uuid/uuid.dart';

import 'platform_vpn.dart';

/// 启动前自动补全与规范化 TOML（hostname、listeners、Android `no_tun` 等）。
class TomlPreparer {
  TomlPreparer._();

  static const _uuid = Uuid();

  /// 解析业务 [configId]：优先参数 → TOML `instance_id` → 随机 UUID。
  static String resolveConfigId(String toml, {String? configId}) {
    if (configId != null && configId.trim().isNotEmpty) {
      return configId.trim();
    }
    try {
      final doc = TomlDocument.parse(toml).toMap();
      final fromToml = doc['instance_id']?.toString().trim();
      if (fromToml != null && fromToml.isNotEmpty) {
        return fromToml;
      }
    } catch (_) {}
    return _uuid.v4();
  }

  /// 按平台注入默认项后返回可交给核心的 TOML 字符串。
  ///
  /// [forAndroidVpn] 为 true 时设置 `flags.no_tun = true`（由系统 VPN 提供 fd）。
  /// 非法 TOML 抛出 [FormatException]。
  static Future<String> prepareForPlatform(
    String toml, {
    required bool forAndroidVpn,
  }) async {
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(TomlDocument.parse(toml).toMap());
    } catch (e) {
      throw FormatException('invalid TOML: $e');
    }

    if (_stringList(data['listeners']).isEmpty && !forAndroidVpn) {
      data['listeners'] = ['tcp://0.0.0.0:11010'];
    }

    final hostname = data['hostname']?.toString().trim() ?? '';
    if (hostname.isEmpty) {
      if (Platform.isAndroid) {
        final device = await PlatformVpn.getDeviceName();
        data['hostname'] = (device == null || device.trim().isEmpty)
            ? 'Android'
            : device.trim();
      } else {
        try {
          data['hostname'] = Platform.localHostname;
        } catch (_) {
          data['hostname'] = 'desktop';
        }
      }
    }

    if (forAndroidVpn) {
      final flags = Map<String, dynamic>.from(
        data['flags'] as Map? ?? <String, dynamic>{},
      );
      flags['no_tun'] = true;
      data['flags'] = flags;
    }

    return TomlDocument.fromMap(data).toString();
  }

  /// 读取 TOML 中的 `manual_routes` 列表。
  static List<String> manualRoutesFromToml(String toml) {
    try {
      final data = TomlDocument.parse(toml).toMap();
      return _stringList(data['manual_routes']);
    } catch (_) {
      return const [];
    }
  }

  /// 读取 TOML 中的 `proxy_cidrs` 列表（用于 Android VPN 路由）。
  static List<String> proxyCidrsFromToml(String toml) {
    try {
      final data = TomlDocument.parse(toml).toMap();
      return _stringList(data['proxy_cidrs']);
    } catch (_) {
      return const [];
    }
  }

  /// 读取 TOML 中的 `mtu`；缺失或非法时默认 1300。
  static int mtuFromToml(String toml) {
    try {
      final data = TomlDocument.parse(toml).toMap();
      final mtu = data['mtu'];
      if (mtu is int) return mtu;
      if (mtu is num) return mtu.toInt();
      return int.tryParse(mtu?.toString() ?? '') ?? 1300;
    } catch (_) {
      return 1300;
    }
  }

  /// 读取 TOML 中的静态 `ipv4` 字段；未配置时返回 `null`。
  static String? staticIpv4FromToml(String toml) {
    try {
      final data = TomlDocument.parse(toml).toMap();
      final ipv4 = data['ipv4']?.toString().trim();
      if (ipv4 == null || ipv4.isEmpty) return null;
      return ipv4;
    } catch (_) {
      return null;
    }
  }

  /// 将 TOML 列表字段规范化为非空字符串列表。
  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
}
